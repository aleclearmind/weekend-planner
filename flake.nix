{
  description = "Weekend Planner — Flutter web app and arm64-v8a Android APK";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
        lib = pkgs.lib;

        pname = "weekend-planner";
        version = "1.0.0";
        flutter = pkgs.flutter;
        jdk = pkgs.jdk17;
        gradle = pkgs.gradle_8;

        androidComposition = pkgs.androidenv.composeAndroidPackages {
          platformVersions = [
            "35"
            "36"
          ];
          buildToolsVersions = [
            "35.0.0"
            "36.0.0"
          ];
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ];
          cmakeVersions = [ "3.22.1" ];
          includeEmulator = false;
          includeSystemImages = false;
          includeSources = false;
        };
        androidSdk = androidComposition.androidsdk;
        sdkRoot = "${androidSdk}/libexec/android-sdk";
        buildToolsVersion = "36.0.0";
        targetPlatform = "android-arm64";

        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./android
            ./lib
            ./web
            ./analysis_options.yaml
            ./pubspec.yaml
            ./pubspec.lock
          ];
        };
        pubspecSrc = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./pubspec.yaml
            ./pubspec.lock
          ];
        };

        dartWithCerts = pkgs.runCommand "dart-with-certs" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p "$out/bin"
          makeWrapper ${flutter.dart}/bin/dart "$out/bin/dart" \
            --add-flags "--root-certs-file=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        '';

        reconstructMavenRepo = pkgs.writeShellApplication {
          name = "reconstruct-maven-repo";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
            pkgs.findutils
          ];
          text = ''
            src="$1"; out="$2"; mkdir -p "$out"
            find "$src" -type f | while read -r f; do
              rel="''${f#"$src"/}"
              g="$(echo "$rel" | cut -d/ -f1)"
              a="$(echo "$rel" | cut -d/ -f2)"
              v="$(echo "$rel" | cut -d/ -f3)"
              fn="$(echo "$rel" | cut -d/ -f5)"
              d="$out/''${g//.//}/$a/$v"
              mkdir -p "$d"
              cp -n "$f" "$d/$fn"
            done
            find "$out" -name '*.module' | while read -r m; do
              d="$(dirname "$m")"
              jq -r '.variants[]?.files[]? | "\(.name) \(.url)"' "$m" 2>/dev/null \
                | sort -u | while read -r name url; do
                [ -z "''${url:-}" ] && continue
                [ "$name" = "$url" ] && continue
                if [ -f "$d/$name" ] && [ ! -f "$d/$url" ]; then
                  cp "$d/$name" "$d/$url"
                fi
              done
            done
          '';
        };

        offlineInit = pkgs.writeText "nix-offline-init.gradle" ''
          def repoUrl = "file://${gradleRepo}"
          beforeSettings { settings ->
              settings.pluginManagement { repositories { maven { url repoUrl } } }
              if (settings.gradle.parent == null) {
                  settings.gradle.allprojects {
                      buildscript { repositories { maven { url repoUrl } } }
                      repositories { maven { url repoUrl } }
                  }
              } else {
                  settings.dependencyResolutionManagement {
                      repositories { maven { url repoUrl } }
                  }
              }
          }
        '';

        gradlewOnline = pkgs.writeShellScript "gradlew" ''
          exec ${gradle}/bin/gradle --no-daemon "$@"
        '';
        gradlewOffline = pkgs.writeShellScript "gradlew" ''
          exec ${gradle}/bin/gradle --offline --no-daemon \
            --init-script ${offlineInit} "$@"
        '';

        androidEnv = ''
          export ANDROID_HOME="${sdkRoot}"
          export ANDROID_SDK_ROOT="${sdkRoot}"
          export JAVA_HOME="${jdk.home}"
          export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkRoot}/build-tools/${buildToolsVersion}/aapt2"
        '';

        mkScratch = ''
          SCRATCH="$TMPDIR/scratch"
          SHM_AVAILABLE_KIB="$(df -Pk /dev/shm 2>/dev/null | awk 'END { print $4 }')"
          if [ "''${SHM_AVAILABLE_KIB:-0}" -ge 8388608 ] \
            && mkdir -p "/dev/shm/${pname}-$$" 2>/dev/null; then
            SCRATCH="/dev/shm/${pname}-$$"
          fi
          mkdir -p "$SCRATCH"
        '';

        pubCache = pkgs.stdenvNoCC.mkDerivation {
          name = "${pname}-pub-cache-${version}";
          src = pubspecSrc;
          nativeBuildInputs = [ flutter ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export PUB_CACHE="$out"
            export NIX_FLUTTER_PUB_DART="${dartWithCerts}/bin/dart"
            flutter config --no-analytics >/dev/null 2>&1 || true
            flutter pub get --enforce-lockfile
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            rm -rf "$out/_temp" "$out/active_roots" "$out/log" "$out/git" "$out/README.md"
            find "$out" -type d -name .cache -prune -exec rm -rf {} +
            runHook postInstall
          '';
          dontFixup = true;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-n9c1stUr1BtKG++UQW2g2GJ2mgos4lFiFAzvidPHpFA=";
        };

        gradleRepo = pkgs.stdenvNoCC.mkDerivation {
          name = "${pname}-gradle-repo-${version}";
          inherit src;
          nativeBuildInputs = [
            flutter
            jdk
            gradle
            androidSdk
            reconstructMavenRepo
            pkgs.git
            pkgs.which
          ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            ${mkScratch}
            export HOME="$SCRATCH/home"
            mkdir -p "$HOME"
            ${androidEnv}
            export PUB_CACHE="$SCRATCH/pub-cache"
            cp -r ${pubCache} "$PUB_CACHE"
            chmod -R u+w "$PUB_CACHE"
            export GRADLE_USER_HOME="$SCRATCH/gradle"
            mkdir -p "$GRADLE_USER_HOME"
            install -m755 ${gradlewOnline} android/gradlew
            flutter config --no-analytics >/dev/null 2>&1 || true
            flutter pub get --offline --enforce-lockfile
            flutter build apk --target-platform ${targetPlatform} --release
            reconstruct-maven-repo \
              "$GRADLE_USER_HOME/caches/modules-2/files-2.1" "$out"
            runHook postBuild
          '';
          dontInstall = true;
          dontFixup = true;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-oHK7u+9yCJ/SeovR9tJAtrxbers+fjnXbqN3vdqqxZ8=";
        };

        apk = pkgs.stdenv.mkDerivation {
          name = "${pname}-${version}-arm64-v8a.apk";
          inherit src;
          nativeBuildInputs = [
            flutter
            jdk
            gradle
            androidSdk
            pkgs.git
            pkgs.which
          ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            ${mkScratch}
            export HOME="$SCRATCH/home"
            mkdir -p "$HOME"
            ${androidEnv}
            export PUB_CACHE="$SCRATCH/pub-cache"
            cp -r ${pubCache} "$PUB_CACHE"
            chmod -R u+w "$PUB_CACHE"
            export GRADLE_USER_HOME="$SCRATCH/gradle"
            mkdir -p "$GRADLE_USER_HOME"
            install -m755 ${gradlewOffline} android/gradlew
            flutter config --no-analytics >/dev/null 2>&1 || true
            flutter pub get --offline --enforce-lockfile
            flutter build apk --target-platform ${targetPlatform} \
              --release --no-pub
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            cp build/app/outputs/flutter-apk/app-release.apk "$out"
            runHook postInstall
          '';
          dontFixup = true;
          passthru = {
            inherit
              pubCache
              gradleRepo
              androidSdk
              flutter
              ;
          };
          meta = with lib; {
            description = "Weekend Planner release APK (arm64-v8a)";
            platforms = [
              "x86_64-linux"
              "aarch64-linux"
            ];
            license = licenses.unfree;
          };
        };

        web = pkgs.stdenv.mkDerivation {
          pname = "${pname}-web";
          inherit version src;
          nativeBuildInputs = [
            flutter
            pkgs.jq
          ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            ${mkScratch}
            export HOME="$SCRATCH/home"
            mkdir -p "$HOME"
            export PUB_CACHE="$SCRATCH/pub-cache"
            cp -r ${pubCache} "$PUB_CACHE"
            chmod -R u+w "$PUB_CACHE"
            flutter config --no-analytics >/dev/null 2>&1 || true
            flutter pub get --offline --enforce-lockfile
            flutter build web --release --no-pub --pwa-strategy=none \
              --no-web-resources-cdn
            # Bundle Roboto so the offline app and screenshots render with the
            # same typography on every machine.
            install -m644 ${pkgs.roboto}/share/fonts/truetype/Roboto-Regular.ttf \
              build/web/assets/fonts/Roboto-Regular.ttf
            install -m644 ${pkgs.roboto}/share/fonts/truetype/Roboto-Medium.ttf \
              build/web/assets/fonts/Roboto-Medium.ttf
            install -m644 ${pkgs.roboto}/share/fonts/truetype/Roboto-Bold.ttf \
              build/web/assets/fonts/Roboto-Bold.ttf
            install -m644 ${pkgs.roboto}/share/fonts/truetype/Roboto-Italic.ttf \
              build/web/assets/fonts/Roboto-Italic.ttf
            jq '. + [{
              "family": "Roboto",
              "fonts": [
                { "asset": "fonts/Roboto-Regular.ttf", "weight": 400 },
                { "asset": "fonts/Roboto-Medium.ttf", "weight": 500 },
                { "asset": "fonts/Roboto-Bold.ttf", "weight": 700 },
                { "asset": "fonts/Roboto-Italic.ttf", "style": "italic" }
              ]
            }]' build/web/assets/FontManifest.json > "$TMPDIR/FontManifest.json"
            install -m644 "$TMPDIR/FontManifest.json" \
              build/web/assets/FontManifest.json
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out"
            cp -r build/web/. "$out/"
            runHook postInstall
          '';
          dontFixup = true;
          meta.description = "Weekend Planner Flutter web build";
        };

        # Exercise the Nix-built site in a phone-sized Chromium viewport and
        # produce the four screenshots published with every release.
        playwrightPython = pkgs.python3.withPackages (ps: [ ps.playwright ]);
        webSmokeRun =
          pkgs.runCommand "${pname}-web-smoke-${version}"
            {
              nativeBuildInputs = [
                playwrightPython
                pkgs.chromium
                pkgs.curl
              ];
              meta.description = "Playwright smoke test and screenshots for Weekend Planner";
            }
            ''
              export HOME="$TMPDIR/home"
              export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
              export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
              mkdir -p "$HOME" "$TMPDIR/screenshots"

              python3 ${./tool/web/serve.py} 8087 ${web} &
              server=$!
              trap 'kill "$server" 2>/dev/null || true' EXIT

              ready=false
              for _ in $(seq 1 30); do
                if curl -fsS -o /dev/null http://127.0.0.1:8087/index.html; then
                  ready=true
                  break
                fi
                sleep 1
              done
              [ "$ready" = true ]

              python3 ${./tool/web/smoke_test.py} \
                http://127.0.0.1:8087/ ${pkgs.chromium}/bin/chromium \
                "$TMPDIR/screenshots"

              mkdir -p "$out"
              for tab in weekends activities people inbox; do
                test -s "$TMPDIR/screenshots/tab_$tab.png"
                install -m644 "$TMPDIR/screenshots/tab_$tab.png" \
                  "$out/${pname}-web-$tab.png"
              done
            '';

        # flake-ci release outputs are individual regular files. These wrappers
        # share one browser run while exposing stable release asset names.
        webReleaseArtifact =
          name: source:
          pkgs.runCommand name
            {
              __structuredAttrs = true;
              ci = [ { action = "release"; } ];
              meta.description = "Weekend Planner screenshot release artifact: ${name}";
            }
            ''
              cp ${webSmokeRun}/${source} "$out"
            '';
        webScreenshotWeekends = webReleaseArtifact "${pname}-web-weekends.png" "${pname}-web-weekends.png";
        webScreenshotActivities = webReleaseArtifact "${pname}-web-activities.png" "${pname}-web-activities.png";
        webScreenshotPeople = webReleaseArtifact "${pname}-web-people.png" "${pname}-web-people.png";
        webScreenshotInbox = webReleaseArtifact "${pname}-web-inbox.png" "${pname}-web-inbox.png";

        serveWeb = pkgs.writeShellApplication {
          name = "weekend-planner";
          runtimeInputs = [ pkgs.python3 ];
          text = ''
            exec python3 ${./tool/web/serve.py} "''${1:-8003}" ${web}
          '';
        };
      in
      {
        packages = {
          default = apk;
          inherit
            apk
            web
            pubCache
            gradleRepo
            androidSdk
            ;
          web-smoke = webSmokeRun;
          web-screenshot-weekends = webScreenshotWeekends;
          web-screenshot-activities = webScreenshotActivities;
          web-screenshot-people = webScreenshotPeople;
          web-screenshot-inbox = webScreenshotInbox;
        };
        checks.web-smoke = webSmokeRun;
        apps.default = {
          type = "app";
          program = "${serveWeb}/bin/weekend-planner";
          meta.description = "Serve Weekend Planner with its RSS proxy";
        };
        devShells.default = pkgs.mkShell {
          packages = [
            flutter
            jdk
            gradle
            androidSdk
          ];
          shellHook = androidEnv;
        };
        formatter = pkgs.nixfmt;
      }
    );
}

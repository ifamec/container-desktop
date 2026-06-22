# Container Desktop

A native SwiftUI desktop interface for [Apple container](https://github.com/apple/container). It manages the service, containers, OCI images, builds, logs, resource statistics, and interactive shells without hiding the underlying CLI commands.

Container Desktop uses Apple's `container` command as its backend. Images remain OCI-compatible, so images from Docker Hub and other standard registries can be used without conversion.

## Contents

- [Requirements](#requirements)
- [Install and run](#install-and-run)
- [Using Container Desktop](#using-container-desktop)
- [Example: run an existing Docker image](#example-run-an-existing-docker-image)
- [Example: build a web server](#example-build-a-web-server)
- [Example: build an existing Dockerfile project](#example-build-an-existing-dockerfile-project)
- [Example: mount an existing website](#example-mount-an-existing-website)
- [Publish an image](#publish-an-image)
- [CLI reference](#common-cli-equivalents)
- [Troubleshooting](#troubleshooting)
- [Development](#development)

## Requirements

- Apple silicon Mac
- macOS 26 or newer
- Apple `container` installed from its signed release package
- Swift 6.2+ to build from source; full Xcode is recommended for signing and packaging

Apple container and Container Desktop currently target Apple silicon. Intel Macs and older macOS releases are not supported.

## Install and run

### 1. Install Apple container

Download the signed installer from the [Apple container releases page](https://github.com/apple/container/releases/latest), then verify the installation:

```sh
container system version
```

Container Desktop does not install or update Apple's CLI automatically.

### 2. Start the service

Open Container Desktop and select **Start Service** on the Dashboard. On first use, Apple container may need to download its Linux kernel and supporting images.

The equivalent terminal command is:

```sh
container system start
```

### 3. Launch Container Desktop from source

```sh
swift build
swift run ContainerDesktop
```

## Using Container Desktop

### Containers

Open **Containers** to see running and stopped containers. Select **Run** to configure a new container:

- **Image:** OCI image reference, such as `docker.io/library/nginx:alpine`
- **Name:** friendly container name
- **Command:** optional command and arguments that replace the image default
- **Environment:** one `KEY=value` entry per line
- **Ports:** one `host-port:container-port` mapping per line
- **Mounts:** one Apple container mount specification per line
- **CPU / Memory:** optional VM limits, such as `2` and `1G`
- **Auto-remove:** delete the container automatically when it stops

The command preview shows exactly what Container Desktop will execute. Saved configurations can be reused from the **Saved** menu.

Select a container to view its state, IP address, resource use, logs, and inspection data. Running containers also provide **Shell**, **Stop**, **Restart**, and **Kill** actions.

### Images

Open **Images** to pull, tag, push, or delete OCI images. Docker Hub is the default registry, but fully qualified references are recommended because they make the image source unambiguous.

Examples:

```text
docker.io/library/alpine:latest
docker.io/library/nginx:alpine
ghcr.io/owner/application:v1
```

### Builds

Open **Builds**, choose a build-context directory, optionally choose a Dockerfile, enter an image tag, and select **Build**. Build output appears live and the operation can be cancelled.

The context directory contains the Dockerfile and every local file available to `COPY` and `ADD` instructions.

## Example: run an existing Docker image

Docker Hub images use the OCI image format supported by Apple container. You do not need Docker Desktop to pull or run them.

This example runs the official nginx Alpine image on port 8080.

### In Container Desktop

1. Open **Images**, select **Pull**, and enter `docker.io/library/nginx:alpine`.
2. Wait for the pull operation to finish. The downloaded image appears under **Images**, not **Containers**—pulling an image does not create a container.
3. Select the pulled image and click **Run**. The image field is filled automatically.
4. Set **Name** to `example-nginx`.
5. Add `8080:80` under **Ports**.
6. Select **Run**. The new container now appears under **Containers**.
7. Open [http://localhost:8080](http://localhost:8080).

Use **Logs** to inspect nginx output and **Shell** to open an interactive shell in Terminal.

### CLI equivalent

```sh
container image pull docker.io/library/nginx:alpine
container run \
  --name example-nginx \
  --detach \
  --publish 8080:80 \
  docker.io/library/nginx:alpine

open http://localhost:8080
```

Clean up afterward:

```sh
container stop example-nginx
container delete example-nginx
container image delete docker.io/library/nginx:alpine
```

## Example: build a web server

Create a directory named `hello-web` containing these two files.

### `Dockerfile`

```dockerfile
FROM docker.io/library/python:3.13-alpine
WORKDIR /site
COPY index.html .
EXPOSE 8000
CMD ["python3", "-m", "http.server", "8000", "--bind", "0.0.0.0"]
```

### `index.html`

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Hello from Apple container</title>
  </head>
  <body>
    <h1>Hello from Container Desktop!</h1>
  </body>
</html>
```

### Build and run in Container Desktop

1. Open **Builds** and choose the `hello-web` directory as the context.
2. Enter `hello-web:latest` as the tag.
3. Select **Build** and wait for the operation to complete.
4. Open **Containers** and select **Run**.
5. Set **Image** to `hello-web:latest` and **Name** to `hello-web`.
6. Add `8080:8000` under **Ports**.
7. Select **Run**, then open [http://localhost:8080](http://localhost:8080).

### CLI equivalent

Run these commands from the `hello-web` directory:

```sh
container build --tag hello-web:latest --file Dockerfile .
container run \
  --name hello-web \
  --detach \
  --publish 8080:8000 \
  hello-web:latest

open http://localhost:8080
```

Inspect the running application:

```sh
container logs hello-web
container stats --no-stream hello-web
container exec --interactive --tty hello-web sh
```

## Example: build an existing Dockerfile project

Most existing Dockerfile projects can be built directly because Apple container uses standard Dockerfiles and OCI images.

Given this project:

```text
my-application/
├── Dockerfile
├── .dockerignore
├── package.json
└── src/
```

### In Container Desktop

1. Open **Builds**.
2. Choose `my-application` as the build context.
3. Leave the Dockerfile field empty to use `my-application/Dockerfile`, or select a differently named file.
4. Enter `my-application:local` as the tag.
5. Select **Build**.
6. After the build succeeds, open **Containers** and run `my-application:local` with the ports and environment variables expected by the application.

### CLI equivalent

```sh
cd my-application
container build --tag my-application:local .
container run \
  --name my-application \
  --detach \
  --publish 3000:3000 \
  --env NODE_ENV=production \
  my-application:local
```

Adjust the port and environment variables for the application. Multi-stage Dockerfiles and images referenced by `FROM` work normally when they support the target platform.

Docker Compose files are not currently imported. Translate each service into a saved Container Desktop run configuration, or use the underlying CLI until project support is added.

## Example: mount an existing website

You can serve local files without rebuilding an image. Replace `/absolute/path/to/site` with a real absolute directory containing an `index.html` file.

### In Container Desktop

Run `docker.io/library/nginx:alpine` with:

- **Name:** `mounted-site`
- **Ports:** `8080:80`
- **Mounts:** `type=bind,source=/absolute/path/to/site,target=/usr/share/nginx/html,readonly`

### CLI equivalent

```sh
container run \
  --name mounted-site \
  --detach \
  --publish 8080:80 \
  --mount type=bind,source=/absolute/path/to/site,target=/usr/share/nginx/html,readonly \
  docker.io/library/nginx:alpine
```

Changes made to the host directory are immediately visible to nginx. The `readonly` option prevents the container from modifying those files.

## Publish an image

Authenticate in Terminal because Container Desktop intentionally does not collect registry passwords:

```sh
container registry login ghcr.io
```

Tag and push the image from Container Desktop's **Images** screen, or use:

```sh
container image tag hello-web:latest ghcr.io/OWNER/hello-web:v1
container image push ghcr.io/OWNER/hello-web:v1
```

Replace `OWNER` with your registry account or organization. Ensure the destination repository exists and your token has permission to publish packages.

## Common CLI equivalents

| Task | Command |
| --- | --- |
| Check versions | `container system version` |
| Start service | `container system start` |
| Stop service | `container system stop` |
| List all containers | `container list --all` |
| Start a container | `container start NAME` |
| Stop a container | `container stop NAME` |
| Delete a container | `container delete NAME` |
| Follow logs | `container logs --follow NAME` |
| Open a shell | `container exec --interactive --tty NAME sh` |
| Show resource use | `container stats NAME` |
| List images | `container image list` |
| Pull an image | `container image pull IMAGE` |
| Build an image | `container build --tag NAME .` |

## Troubleshooting

### Apple container is not installed

Install it from Apple's signed release package. If it is installed in a custom location, enter the executable path under **Settings → CLI path**.

### Service is stopped

Select **Start Service** on the Dashboard or run:

```sh
container system start
```

### A port is already in use

Choose a different host port. For example, change `8080:80` to `8081:80`, then open `http://localhost:8081`.

### An image requires Intel Linux

Prefer images that publish a `linux/arm64` variant. Apple container can use Rosetta for some `linux/amd64` workloads, but Container Desktop does not currently expose the `--rosetta` option in its run form.

### Registry authentication is required

Run `container registry login REGISTRY` in Terminal. Secrets are handled by Apple container and are never added to Container Desktop command history or diagnostics.

### Build cannot find a file

Confirm that the file is inside the selected build-context directory and is not excluded by `.dockerignore`. Dockerfile `COPY` sources are resolved relative to the context, not relative to the Dockerfile location.

## Development

### Test

The command-line-only Swift toolchain on some Macs omits XCTest. The dependency-free core test harness can always be run with:

```sh
swiftc -swift-version 6 \
  Sources/ContainerDesktop/Models.swift \
  Sources/ContainerDesktop/CLI.swift \
  Tests/ContainerDesktopTests/ContainerDesktopTests.swift \
  -o .build/container-desktop-core-tests
.build/container-desktop-core-tests
```

### Package and distribute

Create a release `.app` bundle with:

```sh
./scripts/build-app.sh
```

The finished application is written to:

```text
dist/Container Desktop.app
```

Open the local build with:

```sh
open "dist/Container Desktop.app"
```

By default, the script applies an ad-hoc signature suitable for local development. To sign a distributable build with a Developer ID certificate:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APP_VERSION="0.1.0" \
BUILD_NUMBER="1" \
./scripts/build-app.sh
```

`BUNDLE_IDENTIFIER` can also be supplied to replace the default `com.containerdesktop.app`. Developer ID builds must still be submitted to Apple for notarization before public distribution.

The script performs a release build, packages SwiftPM resources, generates `AppIcon.icns` from the v3 icon, writes bundle metadata, signs the application, and verifies its signature. Container Desktop is intentionally not sandboxed because it launches the installed CLI and accesses user-selected build contexts.

## Current scope

- Service detection and start/stop controls
- Container run, start, stop, restart, kill, delete, inspect, logs, stats, and Terminal shell
- Image pull, tag, push, and delete
- Dockerfile builds with live output and cancellation
- Saved run configurations, command previews, settings, and sanitized diagnostics

Compose projects, automatic CLI installation, registry credential UI, and embedded terminal emulation are intentionally deferred.

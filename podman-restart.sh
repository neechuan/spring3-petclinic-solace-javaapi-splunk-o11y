podman machine stop && podman machine start

podman info --format '{{.Host.RemoteSocket.Path}}' 2>&1 && echo "--- ps ---" && podman ps 2>&1

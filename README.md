# devcontainer
Scripts for creating the CHERIoT dev container

## Notes for use in VSCode
The default user in the container is "cheriot" which created as uid:1000 gid:1000, so as to keep compatibility with earlier images.
If running VSCode on a Linux system the host uid needs to match this so that the mounted filesystem has the correct access.

An alternative is to use bindfs to remount the directory mapping the uid to 1000.  For example assuming your host username is martha (uid:666) then

```
sudo adduser -u 1000 -g 1000 boris
mkdir /home/cheriot-rtos.mapped
sudo bindfs --map=martha/boris /home/cheriot-rtos /home/cheriot-rtos.mapped
```

VScode can now be launched with a dev container from /home/cheriot-rtos.mapped

## Building locally

You can test locally using either Docker or Podman.
The command-line interfaces for the two are the same, so just replace `podman` with `docker` in the examples if you are using Docker.
Clone this repo and then run the following commands from within it:

```sh
podman build --tag 'cheriot-devcontainer-sonata-sim' .
podman run -it --rm localhost/cheriot-devcontainer-sonata-sim:latest
```

This should open up an interactive shell for you where you can make sure that cheriot-tools is setup properly.


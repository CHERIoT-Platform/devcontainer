FROM ghcr.io/cheriot-platform/sail:latest as sail-build
RUN git clone --recurse https://github.com/microsoft/cheriot-sail.git
WORKDIR cheriot-sail
RUN eval $(opam env) && make csim -j4
RUN mkdir /install
RUN cp c_emulator/cheriot_sim /install
RUN cp LICENSE /install/LICENCE-cheriot-sail.txt
RUN cp sail-riscv/LICENCE /install/LICENCE-riscv-sail.txt

FROM ubuntu:24.04 as llvm-download
RUN apt update && apt install -y curl unzip
RUN curl -O https://api.cirrus-ci.com/v1/artifact/github/CHERIoT-Platform/llvm-project/Build%20and%20upload%20artefact%20$(uname -p)/binaries.zip
RUN unzip binaries.zip

FROM ubuntu:24.04 as cheriot-audit
RUN apt update && apt install -y git g++ ninja-build cmake
RUN git clone https://github.com/CHERIoT-Platform/cheriot-audit
RUN mkdir cheriot-audit/build
WORKDIR cheriot-audit/build
RUN cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release
RUN ninja

FROM ubuntu:24.04 as ibex-build
RUN apt update && apt install -y git verilator make g++ ed
WORKDIR /
RUN git clone --recurse https://github.com/microsoft/cheriot-safe.git
WORKDIR cheriot-safe/sim/verilator
RUN ./vgen_stdin
RUN ./vcomp
RUN cp obj_dir/Vswci_vtb /cheriot_ibex_safe_sim
# Patch all.f to build with tracing
RUN echo "10a\n+define+RVFI=1\n.\nw\n" | ed all.f
RUN ./vgen
RUN ./vcomp
RUN cp obj_dir/Vswci_vtb /cheriot_ibex_safe_sim_trace

FROM ubuntu:24.04 AS mpact-build
RUN apt update && apt install -y wget git clang default-jre

RUN machine=$(uname -m) \
    && if [ "$machine" = "x86_64" ]; then bazel="amd64" ; else bazel="arm64" ; fi \
    && wget https://github.com/bazelbuild/bazelisk/releases/download/v1.21.0/bazelisk-linux-$bazel \
    && chmod a+x bazelisk-linux-$bazel \
    && mv bazelisk-linux-$bazel /usr/bin/bazel \
    && git clone https://github.com/google/mpact-cheriot.git
WORKDIR mpact-cheriot
RUN bazel build cheriot:mpact_cheriot

FROM ubuntu:24.04
ARG USERNAME=cheriot

RUN apt update \
    && apt upgrade -y \
    && apt install -y software-properties-common ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && add-apt-repository ppa:xmake-io/xmake \
    && apt update \
    && apt install -y xmake git bsdmainutils python3-pip

# Install uf2convert (needed for Sonata) from pip
RUN python3 -m pip install --break-system-packages --pre git+https://github.com/makerdiary/uf2utils.git@main

# Create the user
RUN useradd -m $USERNAME -o -u 1000 -g 1000 \
    # Add sudo support by group, since UID might alias
    && apt-get install -y sudo \
    && echo %$(id -n -g 1000) ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install the vimrc that configures ALE.
COPY --chown=$USERNAME:$USERNAME vimrc /home/$USERNAME/.vimrc

# Install the Sail and LLVM licenses
RUN mkdir -p /cheriot-tools/licenses
COPY  --from=sail-build /install/LICENCE-cheriot-sail.txt /install/LICENCE-riscv-sail.txt /cheriot-tools/licenses/
COPY --from=llvm-download /Build/install/LLVM-LICENSE.TXT /cheriot-tools/licenses/
# Install the sail simulator.
COPY  --from=sail-build /install/cheriot_sim /cheriot-tools/bin/
# Install the Ibex simulator.
COPY  --from=ibex-build cheriot_ibex_safe_sim /cheriot-tools/bin/
COPY  --from=ibex-build cheriot_ibex_safe_sim_trace /cheriot-tools/bin/
COPY  --from=cheriot-audit /cheriot-audit/build/cheriot-audit /cheriot-tools/bin/
# Install the mpact simulator
COPY  --from=mpact-build /mpact-cheriot/bazel-bin/cheriot/mpact_cheriot /cheriot-tools/bin/
# Install the LLVM tools
RUN mkdir -p /cheriot-tools/bin
COPY --from=llvm-download "/Build/install/bin/clang-13" "/Build/install/bin/lld" "/Build/install/bin/llvm-objcopy" "/Build/install/bin/llvm-objdump" "/Build/install/bin/clangd" "/Build/install/bin/clang-format" "/Build/install/bin/clang-tidy" /cheriot-tools/bin/
# Install the Ibex simulator
# Create the LLVM tool symlinks.
RUN cd /cheriot-tools/bin \
    && ln -s clang-13 clang \
    && ln -s clang clang++ \
    && ln -s lld ld.lld \
    && ln -s llvm-objcopy objcopy \
    && ln -s llvm-objdump objdump \
    && chmod +x *
# Set up the default user.
USER $USERNAME
# Install a vim plugin manager
RUN curl -fLo /home/$USERNAME/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

ENV SHELL /bin/bash
CMD bash

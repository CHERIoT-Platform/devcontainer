################################################
# Helper containers for building dependencies, #
# which are used in the development container. #
################################################

# Build Sail model.
FROM ghcr.io/cheriot-platform/sail:latest AS sail-build
RUN git clone --depth 1 --shallow-submodules --recurse https://github.com/CHERIoT-Platform/cheriot-sail
WORKDIR cheriot-sail
RUN eval $(opam env) && make csim -j4
RUN mkdir /install
RUN cp c_emulator/cheriot_sim /install
RUN cp LICENSE /install/LICENCE-cheriot-sail.txt
RUN cp sail-riscv/LICENCE /install/LICENCE-riscv-sail.txt

# Download LLVM toolchain.
FROM ubuntu:24.04 AS llvm-download
RUN apt update && apt install -y curl unzip
RUN curl -O https://api.cirrus-ci.com/v1/artifact/github/CHERIoT-Platform/llvm-project/Build%20and%20upload%20artefact%20$(uname -p)/binaries.zip
RUN unzip binaries.zip

# Build Audit tool.
FROM ubuntu:24.04 AS cheriot-audit
RUN apt update && apt install -y git g++ ninja-build cmake
RUN git clone --depth 1 https://github.com/CHERIoT-Platform/cheriot-audit
RUN mkdir cheriot-audit/build
WORKDIR cheriot-audit/build
RUN cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release
RUN ninja

# Build Safe simulator.
FROM ubuntu:24.04 AS cheriot-safe-build
RUN apt update && apt install -y git verilator make g++ ed
WORKDIR /
RUN git clone --depth 1 --shallow-submodules --recurse https://github.com/microsoft/cheriot-safe.git
WORKDIR cheriot-safe/sim/verilator
RUN ./vgen -stdin && ./vcomp && mv obj_dir/Vswci_vtb /cheriot_ibex_safe_sim && rm -rf obj_dir
RUN ./vgen -stdin -trace && ./vcomp && mv obj_dir/Vswci_vtb /cheriot_ibex_safe_sim_trace && rm -rf obj_dir
RUN ./vgen -stdin -conf2 && ./vcomp && mv obj_dir/Vswci_vtb /cheriot_kudu_safe_sim && rm -rf obj_dir
RUN ./vgen -stdin -trace -conf2 && ./vcomp && mv obj_dir/Vswci_vtb /cheriot_kudu_safe_sim_trace && rm -rf obj_dir

# Build mpact.
FROM ubuntu:24.04 AS mpact-build
RUN apt update && apt install -y wget git clang default-jre
RUN machine=$(uname -m) \
    && if [ "$machine" = "x86_64" ]; then bazel="amd64" ; else bazel="arm64" ; fi \
    && wget https://github.com/bazelbuild/bazelisk/releases/download/v1.21.0/bazelisk-linux-$bazel \
    && chmod a+x bazelisk-linux-$bazel \
    && mv bazelisk-linux-$bazel /usr/bin/bazel \
    && git clone --depth 1 https://github.com/google/mpact-cheriot.git
WORKDIR mpact-cheriot
RUN bazel build cheriot:mpact_cheriot

# Build Verilator v5.024.
FROM ubuntu:24.04 AS verilator-build
# Install dependencies.
RUN apt update && apt install -y git help2man perl python3 make g++ libfl2 libfl-dev zlib1g zlib1g-dev autoconf flex bison
WORKDIR /
# Clone Verilator repo and perform build.
RUN git clone --depth 1 -b v5.024 https://github.com/verilator/verilator
WORKDIR verilator
RUN mkdir install
RUN autoconf \
    && ./configure --prefix=/verilator/install \
    && make -j `nproc` \
    && make install

# Build Sonata simulator and boot stub.
FROM ubuntu:24.04 AS sonata-build
# Sonata dependencies.
RUN apt update && apt install -y git python3 python3-venv build-essential libelf-dev libxml2-dev
# Install LLVM for sim boot stub.
RUN mkdir -p /cheriot-tools/bin
COPY --from=llvm-download "/Build/install/bin/clang-[0-9][0-9]" "/Build/install/bin/lld" "/Build/install/bin/llvm-objcopy" "/Build/install/bin/llvm-objdump" "/Build/install/bin/clangd" "/Build/install/bin/clang-format" "/Build/install/bin/clang-tidy" "/Build/install/bin/lldb" "/Build/install/lib/liblldb.so" /cheriot-tools/bin/
# Create the LLVM tool symlinks.
RUN cd /cheriot-tools/bin \
    && ln -s clang-[0-9][0-9] clang \
    && ln -s clang clang++ \
    && ln -s lld ld.lld \
    && ln -s llvm-objcopy objcopy \
    && ln -s llvm-objdump objdump \
    && chmod +x *
COPY --from=verilator-build "/verilator/install" /verilator
WORKDIR /
# Build Sonata simulator.
RUN git clone --depth 1 https://github.com/lowRISC/sonata-system
WORKDIR sonata-system
RUN python3 -m venv .venv \
    && . .venv/bin/activate \
    && pip install -r python-requirements.txt \
    && export PATH=/verilator/bin:$PATH \
    && fusesoc --cores-root=. run --target=sim --tool=verilator --setup --build lowrisc:sonata:system
RUN cp build/lowrisc_sonata_system_0/sim-verilator/Vtop_verilator /sonata_simulator
# Build Sonata simulator boot stub.
WORKDIR sw/cheri/sim_boot_stub
RUN export PATH=/cheriot-tools/bin:$PATH \
    && make
RUN cp sim_sram_boot_stub /sonata_simulator_sram_boot_stub && cp sim_boot_stub /sonata_simulator_hyperram_boot_stub

##########################################
# Set up the main development container. #
##########################################

FROM ubuntu:24.04
ARG USERNAME=cheriot

RUN apt update \
    && apt upgrade -y \
    && apt install -y software-properties-common ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && add-apt-repository ppa:xmake-io/xmake \
    && apt update \
    && apt install -y xmake git bsdmainutils python3-pip

# Work around xmake 3.0.0 being buggy.
COPY xmake.diff patch.sh /tmp
RUN sh /tmp/patch.sh

# Install uf2convert (needed for Sonata) from pip.
RUN python3 -m pip install --break-system-packages --pre git+https://github.com/makerdiary/uf2utils.git@main

# Create the user.
# The second user is for the github actions runner.
RUN useradd -m $USERNAME -o -u 1000 -g 1000 \
    && useradd -m github-ci -o -u 1001 -g 1000 \
    && groupadd -o -g 1000 $USERNAME \
    # Add sudo support by group, since UID might alias.
    && apt-get install -y sudo \
    && echo %$(id -n -g 1000) ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install the vimrc that configures ALE.
COPY --chown=$USERNAME:$USERNAME vimrc /home/$USERNAME/.vimrc

# Install the Sail, LLVM and Sonata licenses.
RUN mkdir -p /cheriot-tools/licenses
COPY --from=sail-build /install/LICENCE-cheriot-sail.txt /install/LICENCE-riscv-sail.txt /cheriot-tools/licenses/
COPY --from=llvm-download /Build/install/LLVM-LICENSE.TXT /cheriot-tools/licenses/
COPY --from=sonata-build /sonata-system/LICENSE /cheriot-tools/licenses/SONATA-LICENSE.txt
# Install the sail simulator.
RUN mkdir -p /cheriot-tools/bin
COPY --from=sail-build /install/cheriot_sim /cheriot-tools/bin/
# Install the Ibex simulator.
COPY --from=cheriot-safe-build cheriot_ibex_safe_sim /cheriot-tools/bin/
COPY --from=cheriot-safe-build cheriot_ibex_safe_sim_trace /cheriot-tools/bin/
COPY --from=cheriot-safe-build cheriot_kudu_safe_sim /cheriot-tools/bin/
COPY --from=cheriot-safe-build cheriot_kudu_safe_sim_trace /cheriot-tools/bin/
# Install audit tool.
COPY --from=cheriot-audit /cheriot-audit/build/cheriot-audit /cheriot-tools/bin/
# Install the mpact simulator.
COPY --from=mpact-build /mpact-cheriot/bazel-bin/cheriot/mpact_cheriot /cheriot-tools/bin/
# Install the Sonata simulator and boot stub.
COPY --from=sonata-build sonata_simulator /cheriot-tools/bin/
RUN mkdir -p /cheriot-tools/elf
COPY --from=sonata-build sonata_simulator_sram_boot_stub sonata_simulator_hyperram_boot_stub /cheriot-tools/elf/
# Install the LLVM tools.
COPY --from=llvm-download "/Build/install/bin/clang-[0-9][0-9]" "/Build/install/bin/lld" "/Build/install/bin/llvm-objcopy" "/Build/install/bin/llvm-objdump" "/Build/install/bin/llvm-strip" "/Build/install/bin/clangd" "/Build/install/bin/clang-format" "/Build/install/bin/clang-tidy" "/Build/install/bin/lldb" "/Build/install/lib/liblldb.so" /cheriot-tools/bin/
# Create the LLVM tool symlinks.
RUN cd /cheriot-tools/bin \
    && ln -s clang-[0-9][0-9] clang \
    && ln -s clang clang++ \
    && ln -s lld ld.lld \
    && ln -s llvm-objcopy objcopy \
    && ln -s llvm-objdump objdump \
    && ln -s llvm-strip strip \
    && chmod +x * \
    && cd ../elf \
    && ln -s sonata_simulator_sram_boot_stub sonata_simulator_boot_stub
# Set up the default user.
USER $USERNAME
# Install a vim plugin manager.
RUN curl -fLo /home/$USERNAME/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Enter shell.
ENV SHELL /bin/bash
CMD bash

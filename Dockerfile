FROM ubuntu:22.04 as sail-build
RUN apt update && apt install -y opam z3 libgmp-dev cvc4 pkg-config zlib1g-dev make
RUN opam init -y
RUN test -r /root/.opam/opam-init/init.sh && . /root/.opam/opam-init/init.sh > /dev/null 2> /dev/null || true
RUN opam pin -y https://codeload.github.com/rems-project/sail/zip/refs/tags/0.15
RUN git clone --recurse https://github.com/microsoft/cheriot-sail.git
WORKDIR cheriot-sail
RUN git config --global user.name 'No One'
RUN git config --global user.email 'noone@nowhere.com'
RUN make patch_sail_riscv
RUN eval $(opam env) && make csim -j4
RUN mkdir /install
RUN cp c_emulator/cheriot_sim /install
RUN cp LICENSE /install/LICENCE-cheriot-sail.txt
RUN cp sail-riscv/LICENCE /install/LICENCE-riscv-sail.txt

FROM ubuntu:22.04 as llvm-download
RUN apt update && apt install -y curl unzip
RUN curl -O https://api.cirrus-ci.com/v1/artifact/github/CHERIoT-Platform/llvm-project/Build%20and%20upload%20artefact/binaries.zip
RUN unzip binaries.zip

FROM ubuntu:22.04
ARG USERNAME=cheriot

RUN apt update \
    && apt upgrade -y \
    && apt install -y software-properties-common \
    && add-apt-repository ppa:xmake-io/xmake \
    && apt update \
    && apt install -y xmake git clang

# Create the user
RUN useradd -m $USERNAME \
    # Add sudo support.
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME
# Install the Sail and LLVM licenses
RUN mkdir -p /cheriot-tools/licenses
COPY  --from=sail-build /install/LICENCE-cheriot-sail.txt /install/LICENCE-riscv-sail.txt /cheriot-tools/licenses/
COPY --from=llvm-download /Build/install/LLVM-LICENSE.TXT /cheriot-tools/licenses/
# Install the sail simulator.
COPY  --from=sail-build /install/cheriot_sim /cheriot-tools/bin/
# Install the LLVM tools
RUN mkdir -p /cheriot-tools/bin
COPY --from=llvm-download "/Build/install/bin/clang-13" "/Build/install/bin/lld" "/Build/install/bin/llvm-objdump" "/Build/install/bin/clangd" "/Build/install/bin/clang-format" "/Build/install/bin/clang-tidy" /cheriot-tools/bin/
# Create the LLVM tool symlinks.
RUN cd /cheriot-tools/bin \
    && ln -s clang-13 clang \
    && ln -s clang clang++ \
    && ln -s lld ld.lld \
    && ln -s llvm-objdump objdump \
    && chmod +x *
# Set up the default user.
USER $USERNAME
ENV SHELL /bin/bash
CMD bash

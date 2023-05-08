# Use the respective Makefile to build the image.
FROM nvidia/cuda:11.3.1-devel-ubuntu18.04

ENV SHELL /bin/bash
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES compute,utility
ENV PATH /usr/local/cuda-11.3/bin:$PATH
ENV PATH /home/jovyan/.local/bin:$PATH
ENV LD_LIBRARY_PATH /usr/local/cuda-11.3/lib64:$LD_LIBRARY_PATH
ENV TCNN_CUDA_ARCHITECTURES ${CUDA_ARCH_VER}
ENV HOME /home/jovyan

ARG MINIFORGE_ARCH="x86_64"
# renovate: datasource=github-tags depName=conda-forge/miniforge versioning=loose
ARG MINIFORGE_VERSION=4.10.1-4
ARG PIP_VERSION=21.1.2
ARG PYTHON_VERSION=3.8.10

WORKDIR /home/jovyan

# set shell to bash
SHELL ["/bin/bash", "-c"]

# install - useful linux packages
RUN export DEBIAN_FRONTEND=noninteractive \
 && apt-get -yq update \
 && apt-get -yq install --no-install-recommends \
    ca-certificates \
    ssh-client \
    curl \
    git \
    gnupg \
    gnupg2 \
    locales \
    lsb-release \
    software-properties-common \
    tzdata \
    unzip \
    cmake \
    htop \
    vim \
    wget \
    zip \
    make \
    gcc \
    g++ \
    build-essential \
    libopenexr-dev \
    libxi-dev \
    libglfw3-dev \
    libglew-dev \
    libomp-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxrandr-dev \
    libboost-all-dev \
    libeigen3-dev \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# install - gcloud SDK
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
  && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \ | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
  && apt-get update \
  && apt-get install google-cloud-cli -y --no-install-recommends

COPY . /home/jovyan

# setup environment for conda
ENV CONDA_DIR /opt/conda
ENV PATH "${CONDA_DIR}/bin:${PATH}"
RUN mkdir -p ${CONDA_DIR} \
 && echo ". /opt/conda/etc/profile.d/conda.sh" >> ${HOME}/.bashrc \
 && echo ". /opt/conda/etc/profile.d/conda.sh" >> /etc/profile \
 && echo "conda activate base" >> ${HOME}/.bashrc \
 && echo "conda activate base" >> /etc/profile \
 && chown -R ${NB_USER}:users ${CONDA_DIR} \
 && chown -R ${NB_USER}:users ${HOME}

# install - conda, pip, python
RUN curl -sL "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-Linux-${MINIFORGE_ARCH}.sh" -o /tmp/Miniforge3.sh \
 && curl -sL "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-Linux-${MINIFORGE_ARCH}.sh.sha256" -o /tmp/Miniforge3.sh.sha256 \
 && echo "$(cat /tmp/Miniforge3.sh.sha256 | awk '{ print $1; }') /tmp/Miniforge3.sh" | sha256sum --check \
 && rm /tmp/Miniforge3.sh.sha256 \
 && /bin/bash /tmp/Miniforge3.sh -b -f -p ${CONDA_DIR} \
 && rm /tmp/Miniforge3.sh \
 && conda config --system --set auto_update_conda false \
 && conda config --system --set show_channel_urls true \
 && echo "conda ${MINIFORGE_VERSION:0:-2}" >> ${CONDA_DIR}/conda-meta/pinned \
 && echo "python ${PYTHON_VERSION}" >> ${CONDA_DIR}/conda-meta/pinned \
 && conda install -y -q \
    python=${PYTHON_VERSION} \
    conda=${MINIFORGE_VERSION:0:-2} \
    pip=${PIP_VERSION} \
 && conda update -y -q --all \
 && conda clean -a -f -y \
 && chown -R ${NB_USER}:users ${CONDA_DIR} \
 && chown -R ${NB_USER}:users ${HOME}

# update cmake
RUN apt-get purge --auto-remove -y cmake \
  && apt-get -yq update \
  && wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null \
  && apt-add-repository "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" \
  && apt-get -yq update \
  && apt-get --no-install-recommends -y install kitware-archive-keyring \
  && rm /etc/apt/trusted.gpg.d/kitware.gpg \
  && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6AF7F09730B3F0A4 \
  && apt-get -yq update \
  && apt-get install --no-install-recommends -y cmake

RUN pip install torch==1.12.1+cu113 torchvision==0.13.1+cu113 --extra-index-url https://download.pytorch.org/whl/cu113

RUN python3 -m pip install --upgrade pip \
  && python3 -m pip install --upgrade setuptools \
  && python3 -m pip install -r requirements.txt \
  && python3 -m pip install -r ./thirdparty/gtsam/python/requirements.txt \
  && cmake ./thirdparty/instant-ngp -B build_ngp \
  && cmake --build build_ngp --config RelWithDebInfo -j \
  && cmake ./thirdparty/gtsam -DGTSAM_BUILD_PYTHON=1 -DGTSAM_USE_SYSTEM_EIGEN=ON -B build_gtsam \
  && cmake --build build_gtsam --config RelWithDebInfo -j1 \
  && cd build_gtsam \
  && make python-install

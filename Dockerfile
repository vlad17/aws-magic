FROM tensorflow/tensorflow:latest-gpu-py3 

# ML-related python libs
RUN pip --no-cache-dir install \
    numpy scipy matplotlib jupyter pandas tabulate keras six sympy \
    Pillow h5py sklearn
RUN pip install jupyter_contrib_nbextensions

# Update repo index with cmake
RUN add-apt-repository ppa:george-edison55/cmake-3.x -y
RUN apt-get update

# Add a sudo-user, mluser, for a more familiar work env
RUN apt-get --assume-yes install sudo
RUN useradd -ms /bin/bash mluser
RUN passwd -d mluser
RUN usermod -aG sudo mluser
RUN touch /home/mluser/.sudo_as_admin_successful
RUN echo "mluser ALL=NOPASSWD: ALL" > /etc/sudoers.d/mluser
RUN echo >> /etc/sudoers.d/mluser
USER mluser
WORKDIR /home/mluser

# Install my emacs config
RUN sudo apt-get --assume-yes install build-essential cmake emacs git tmux
RUN mkdir -p dev && git clone https://github.com/vlad17/misc.git
RUN /bin/bash misc/fresh-start/emacs-install.sh
RUN /bin/bash misc/fresh-start/config.sh
RUN echo "export USER=mluser" >> .bashrc

# jupyter config
RUN sudo pip install yapf
RUN jupyter contrib nbextension install --user
RUN jupyter nbextension enable hide_input/main
RUN jupyter nbextension enable code_prettify/code_prettify
RUN jupyter nbextension enable code_font_size/code_font_size
RUN jupyter nbextension enable comment-uncomment/main
RUN jupyter nbextension enable spellchecker/main
RUN jupyter nbextension enable autoscroll/main

# Tensorboard
EXPOSE 6006
# Jupyter ports
EXPOSE 8888

CMD ["/bin/bash"]

FROM floydhub/tensorflow:1.4.1-py3_aws.19

# Update repo index with cmake
RUN add-apt-repository ppa:george-edison55/cmake-3.x -y
RUN apt-get update
RUN apt-get --assume-yes install build-essential cmake git

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
RUN sudo apt-get --assume-yes install emacs tmux
RUN mkdir -p dev
RUN git clone https://github.com/vlad17/misc.git
RUN /bin/bash misc/fresh-start/emacs-install.sh
RUN /bin/bash misc/fresh-start/config.sh
RUN echo "export USER=mluser" >> .bashrc
ENV USER=mluser

# ML/computing-related python libs
RUN sudo apt-get --assume-yes install graphviz htop xvfb texlive-full
RUN sudo -H pip --no-cache-dir install \
    numpy scipy matplotlib jupyter pandas tabulate keras six sympy \
    Pillow h5py sklearn pydot graphviz jupyter_contrib_nbextensions \
    bcolz pydot graphviz contexttimer contexttimer autopep8 \
    flake8 pylint cloudpickle ray joblib gym line_profiler
    
# jupyter config
RUN sudo -H pip install yapf
RUN jupyter contrib nbextension install --user
RUN jupyter nbextension enable hide_input/main
RUN jupyter nbextension enable code_prettify/code_prettify
RUN jupyter nbextension enable code_font_size/code_font_size
RUN jupyter nbextension enable comment-uncomment/main
RUN jupyter nbextension enable spellchecker/main
RUN jupyter nbextension enable autoscroll/main

# emacs server
RUN emacs --daemon

# Tensorboard
EXPOSE 6006
# Jupyter ports
EXPOSE 8888

CMD ["/bin/bash"]


# -*- coding: utf-8 -*-

import os, time
from fabric.api import *
from fabric.contrib.project import rsync_project
from contextlib import contextmanager

env.local_stage = os.getcwd()
env.roledefs = {
        'testing': ['alioth.lib.pdx.edu'],
        'production': ['nomad.lib.pdx.edu'],
}
env.time_stamp = time.strftime("%Y%m%d%H%M%S")
env.user = 'patronload'
env.app_dir = '/srv/patronload'
env.venv_dir = os.path.join(env.app_dir, 'venv')


@contextmanager
def source_virtualenv():
    with prefix('source {0}'.format(os.path.join(env.venv_dir, 'bin/activate'))):
        yield


@task 
def test():
    run('ls -altr {0}'.format(env.app_dir))
    run('whoami')
    with source_virtualenv():
        run('which python')


@task
def deploy():
    with settings(warn_only=True):
        rsync_project(
                remote_dir='{0}'.format(env.app_dir),
                local_dir='./',
                exclude=('*.pyc', '*.md', '.git*', '*.swp', 'fabfile.py', 'venv', 'tmp', 
                    'sftp', 'archived', 'config/patronload.config.example', '.vscode'),)
        with cd('{0}'.format(env.app_dir)):
            if run('test -d venv').failed:
                run('virtualenv venv -p /usr/bin/python2.7')
            with source_virtualenv():
                run('pip install -r requirements.txt')


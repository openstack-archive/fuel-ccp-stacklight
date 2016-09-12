#!/usr/bin/env python
#
#    Copyright 2016 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#

# Global imports
# --------------
import argparse
import glob
import jinja2
import logging
import os
import pyinotify
import sys
import yaml

# inotify dir/file watcher extension requirements
# -----------------------------------------------
from pyinotify import WatchManager, Notifier, ProcessEvent, ALL_EVENTS

# Jinja2 templating requirements
# ------------------------------
from jinja2 import Environment, FileSystemLoader

# Logging extension requirements
# ------------------------------
from logging.config import fileConfig

# Best practice code for inotify
# ------------------------------
try:  # Python 2.7+
    from logging import NullHandler
except ImportError:
    class NullHandler(logging.Handler):
        def emit(self, record):
            pass

# Logging initialization
# ----------------------


def logger_init(cfg_file):
    """Initialize logger instance."""
    log = logging.getLogger()
    log.setLevel(logging.DEBUG)
    try:
        log.debug('Looking for log configuration file: %s' % (cfg_file))
        # Default logging configuration file
        fileConfig(cfg_file)
    except Exception as e:
        # Only add handler if not already done
        if len(log.handlers) == 0:
            # Hardcoded default logging configuration if no/bad config file
            console_handler = logging.StreamHandler(sys.stdout)
            console_handler.setFormatter(
                logging.Formatter(
                    "[%(asctime)s.%(msecs)03d %(name)s %(levelname)s] %(message)s",
                    "%Y-%m-%d %H:%M:%S"))
            log.addHandler(console_handler)
            log.setLevel(logging.DEBUG)
            log.debug('Defaulting to stdout')
    return log

# Class for debugging inotify extension
#
# This prints all event for which user
# registered in default logger
# -------------------------------------


class DebugAllEvents(ProcessEvent):
    """
    Dummy class used to print events strings representations. For instance this
    class is used from command line to print all received events to stdout.
    """
    def my_init(self, out=None):
        """
        @param out: Logger where events will be written.
        @type out: Object providing a valid logging object interface.
        """
        if out is None:
            global log
            out = log
        self._out = out

    def process_default(self, event):
        """
        Writes event string representation to logging object provided to
        my_init().

        @param event: Event to be processed. Can be of any type of events but
                      IN_Q_OVERFLOW events (see method process_IN_Q_OVERFLOW).
        @type event: Event instance
        """
        self._out.debug(str(event))

# Convert YAML file containing alarms into lua code
# -------------------------------------------------


def yaml2lua(lua_dest_file, yaml_file, template_file):
    global log
    log.info('Converting alarm YAML file %s to %s using template %s'
             % (yaml_file, lua_dest_file, template_file))
    try:
        with open(yaml_file, 'r') as stream:
            try:
                alarms_yaml = yaml.load(stream)
            except yaml.YAMLError as exc:
                log.Error('Error parsing file: %s' % (exc))
                return False
        try:
            alarms = alarms_yaml['alarms']
        except KeyError:
            log.Error('Error parsing file: can not find alarms key')
            return False
        j2_env = Environment(
            loader=FileSystemLoader(os.path.dirname(template_file)),
            trim_blocks=True)
        template = j2_env.get_template(os.path.basename(template_file))
        with open(lua_dest_file, 'w') as stream:
            try:
                stream.write(template.render(alarms=alarms))
            except Exception as e:
                log.Error('Error got exception: %s' % (e))
                return False

    except Exception as e:
        log.Error('Error got exception: %s' % (e))
        return False
    return True

# Command line argument parsing
# -----------------------------


def cmd_line_parser():
    global log
    parser = argparse.ArgumentParser(
        description="""Alarm manager watches for new alarms definitions
        in specified directory and applies them TBC ...
        """
    )
    parser.add_argument(
        '-c', '--config',
        help='log level and format configuration file (default %s)'
        % (dflt_config),
        default=dflt_config,
        dest='config'
    )
    parser.add_argument(
        '-d', '--dest',
        help='destination LUA file (default %s)' % (dflt_dest),
        default=dflt_dest,
        dest='dest'
    )
    parser.add_argument(
        '-t', '--template',
        help='LUA template file (default %s)' % (dflt_template),
        default=dflt_template,
        dest='template'
    )
    parser.add_argument(
        '-w', '--watch-path',
        help='path to watch for changes',
        required=True,
        dest='watchpath'
    )
    args = parser.parse_args()
    log.info('Watch path: %s\n\tConfig: %s\n\tTemplate: %s' % (args.watchpath, args.config, args.template))
    log = logger_init(args.config)

    if not os.path.isdir(args.watchpath) or not os.access(args.watchpath, os.R_OK):
        log.error("{} not a directory or is not readable".format(args.watchpath))
        sys.exit(1)

    if not os.path.isfile(args.template) or not os.access(args.template, os.R_OK):
        log.error("{} not a file or is not readable".format(args.template))
        sys.exit(1)

    src = os.path.join(args.watchpath, dflt_alarm_file)
    log.info('Looking for existing readable file: %s' % (src))
    if os.access(src, os.R_OK):
        if not yaml2lua(
                args.dest,
                src,
                args.template
        ):
            log.error('Error converting YAML alarms into LUA code')
    # watch manager instance
    wm = WatchManager()
    # notifier instance and init
    notifier = Notifier(wm, default_proc_fun=DebugAllEvents())
    # What mask to apply
    mask = ALL_EVENTS
    log.debug('Start monitoring of %s' % args.watchpath)
    wm.add_watch(args.watchpath, mask, rec=False, auto_add=False, do_glob=False)
    # Loop forever (until sigint signal get caught)
    notifier.loop(callback=None)

dflt_config = '/etc/stacklight/alarming/config/alarm-manager.ini'
dflt_template = '/etc/stacklight/alarming/templates/lua_alarming_template.j2'
dflt_dest = '/tmp/test.lua'
dflt_alarm_file = 'alarming.yaml'
log = logger_init(None)
if __name__ == '__main__':
    cmd_line_parser()

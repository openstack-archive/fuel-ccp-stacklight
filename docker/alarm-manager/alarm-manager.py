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
import jinja2
import logging
import os
import pyinotify
import sys
import yaml
import pdb

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
    except Exception:
        # Only add handler if not already done
        if len(log.handlers) == 0:
            # Hardcoded default logging configuration if no/bad config file
            console_handler = logging.StreamHandler(sys.stdout)
            fmt_str = "[%(asctime)s.%(msecs)03d %(name)s %(levelname)s] " \
                      "%(message)s"
            console_handler.setFormatter(
                logging.Formatter(fmt_str, "%Y-%m-%d %H:%M:%S"))
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

# Placeholder for YAML alarms structure validation
# ------------------------------------------------


def validate_alarms(alarms_yaml):
    global log
    log.info('Validating YAML alarms structure')
    return True

# Convert YAML file containing alarms into lua code
# -------------------------------------------------


def yaml2lua(lua_dest_file, lua_cfg_dest_dir, yaml_file, template_file, cfg_template_file):
    global log
    log.info('Converting alarm YAML file %s to %s'
             % (yaml_file, lua_dest_file))
    log.info('Using LUA template %s and LUA config template %s'
             % (template_file, cfg_template_file))
    log.info('Configuration files stored in %s'
             % (lua_cfg_dest_dir))
    try:
        # Open file and retrieve YAML structure if correctly formed
        with open(yaml_file, 'r') as stream:
            try:
                alarms_yaml = yaml.load(stream)
            except yaml.YAMLError as exc:
                log.error('Error parsing file: %s' % (exc))
                return False
        # Check overall validity of alarms definitions
        if not validate_alarms(alarms_yaml):
            log.error('Error validating alarms definitions')
            return False
        # Try to retrieve alarms definitions
        try:
            alarms = alarms_yaml['alarms']
        except KeyError:
            log.error('Error parsing file: can not find alarms key')
            return False
        # Try to retrieve alarms groups definitions
        try:
            cluster_alarms = alarms_yaml['node_cluster_alarms']
        except KeyError:
            log.error('Error parsing file: can not find node_cluster_alarms key')
            return False
        # Produce LUA file corresponding to alarms
        j2_env = Environment(
            loader=FileSystemLoader(os.path.dirname(template_file)),
            trim_blocks=True)
        template = j2_env.get_template(os.path.basename(template_file))
        with open(lua_dest_file, 'w') as stream:
            try:
                stream.write(template.render(alarms=alarms))
            except Exception as e:
                log.error('Error got exception: %s' % (e))
                return False
        j2_cfg_env = Environment(
            loader=FileSystemLoader(os.path.dirname(cfg_template_file)),
            trim_blocks=True)
        cfg_template = j2_cfg_env.get_template(os.path.basename(cfg_template_file))
        #pdb.set_trace()
        afd_cluster_name = cluster_alarms.keys()[0]
        for key in cluster_alarms[afd_cluster_name]['alarms'].keys():
            cfg_file = 'afd_node_%s_%s_alarms' % (afd_cluster_name,key)
            lua_cfg_dest_file = os.path.join(lua_cfg_dest_dir, "%s.cfg" % (cfg_file))
            log.debug('Writing config file: %s' % lua_cfg_dest_file)
            with open(lua_cfg_dest_file, 'w') as stream:
                try:
                    stream.write(cfg_template.render(
                        afd_file=cfg_file,
                        afd_cluster_name=afd_cluster_name,
                        afd_logical_name=key
                    ))
                except Exception as e:
                    log.error('Error got exception: %s' % (e))
                    return False
    except Exception as e:
        log.error('Error got exception: %s' % (e))
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
        '-d', '--dest', '--destination',
        help='destination LUA file (default %s)' % (dflt_dest),
        default=dflt_dest,
        dest='dest'
    )
    parser.add_argument(
        '-D', '--destdir', '--destination-directory',
        help='destination path for LUA plugins configuration files (default %s)' % (dflt_dest_dir),
        default=dflt_dest_dir,
        dest='dest_dir'
    )
    parser.add_argument(
        '-t', '--template',
        help='LUA template file (default %s)' % (dflt_template),
        default=dflt_template,
        dest='template'
    )
    parser.add_argument(
        '-T', '--config-template',
        help='LUA plugins configuration template file (default %s)' % (dflt_cfg_template),
        default=dflt_cfg_template,
        dest='cfg_template'
    )
    parser.add_argument(
        '-w', '--watch-path',
        help='path to watch for changes',
        required=True,
        dest='watch_path'
    )
    args = parser.parse_args()
    log.info('Watch path: %s\n\tConfig: %s\n\tTemplate: %s'
             % (args.watch_path, args.config, args.template))
    log = logger_init(args.config)

    if (
            not os.path.isdir(args.watch_path) or
            not os.access(args.watch_path, os.R_OK)):
        log.error("{} not a directory or is not readable"
                  .format(args.watch_path))
        sys.exit(1)

    if (
            not os.path.isdir(args.dest_dir) or
            not os.access(args.dest_dir, os.W_OK)):
        log.error("{} not a directory or is not writable"
                  .format(args.dest_dir))
        sys.exit(1)

    if (
            not os.path.isfile(args.template) or
            not os.access(args.template, os.R_OK)):
        log.error("{} not a file or is not readable".format(args.template))
        sys.exit(1)

    if (
            not os.path.isfile(args.cfg_template) or
            not os.access(args.cfg_template, os.R_OK)):
        log.error("{} not a file or is not readable".format(args.cfg_template))
        sys.exit(1)

    src = os.path.join(args.watch_path, dflt_alarm_file)
    log.info('Looking for existing readable file: %s' % (src))
    if os.access(src, os.R_OK):
        if not yaml2lua(
                args.dest,
                args.dest_dir,
                src,
                args.template,
                args.cfg_template
        ):
            log.error('Error converting YAML alarms into LUA code')
    # watch manager instance
    wm = WatchManager()
    # notifier instance and init
    notifier = Notifier(wm, default_proc_fun=DebugAllEvents())
    # What mask to apply
    mask = ALL_EVENTS
    log.debug('Start monitoring of %s' % args.watch_path)
    wm.add_watch(args.watch_path, mask, rec=False,
                 auto_add=False, do_glob=False)
    # Loop forever (until sigint signal get caught)
    notifier.loop(callback=None)

dflt_config = '/etc/stacklight/alarming/config/alarm-manager.ini'
dflt_template = '/etc/stacklight/alarming/templates/lua_alarming_template.j2'
dflt_cfg_template = '/etc/stacklight/alarming/templates/lua_config_template.j2'
dflt_dest = '/tmp/test.lua'
dflt_dest_dir = '/tmp'
dflt_alarm_file = 'alarms.yaml'
log = logger_init(None)
if __name__ == '__main__':
    cmd_line_parser()

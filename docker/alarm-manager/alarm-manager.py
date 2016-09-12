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

# Global variables initialization
# -------------------------------

dflt_cfg_dir = '/etc/stacklight/alarming'
dflt_config = dflt_cfg_dir + '/config/alarm-manager.ini'
dflt_template = dflt_cfg_dir + '/templates/lua_alarming_template.j2'
dflt_cfg_template = dflt_cfg_dir + '/templates/lua_config_template.j2'
dflt_dest_dir = '/opt/ccp/lua/modules/stacklight_alarms'
dflt_cfg_dest_dir = '/var/lib/hindsight/load/analysis'
dflt_alarm_file = 'alarms.yaml'

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

log = logger_init(None)

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

# Check alarm entry for field existence and type
# ----------------------------------------------


def check_alarm_entry_field(alarm, field, ftype):
    try:
        akeys = alarm.keys()
        # Field lookup
        if field not in akeys:
            log.error('Error parsing file: alarm entry does ' +
                      'not have a %s field: %s'
                      % (field, alarm))
            return False
        # Do we need to check for proper type too ?
        if ftype is not None:
            vfield = alarm[field]
            vftype = type(vfield)
            # Check for proper type
            if vftype is not ftype:
                log.error('Error parsing file: alarm entry does ' +
                          'not have a field %s is not of type ' +
                          '%s: found %s [%s]'
                          % (field, ftype.__name__, vftype.__name__, alarm))
                return False
    except Exception as e:
        log.error('Error checking for %s: %s' % (field, e))
        return False
    return True

# YAML alarms structure validation
#
# TODO: do not return false right away
# when processing lists so that most errors
# are reported at once allowing for faster
# achievement of correctness
# -----------------------------------------


def validate_yaml(alarms_yaml):
    log.info('Validating YAML alarms structure')
    ctx = ''
    try:
        # Try to retrieve alarms groups definitions
        # and check overall validity
        cluster_alarms = alarms_yaml['node_cluster_alarms']
        ckeys = cluster_alarms.keys()
        # Must have only one sub entry = default
        if len(ckeys) != 1:
            log.error('Error parsing file: node_cluster_alarms should ' +
                      'have only one subentry')
            return False
        if ckeys[0] != 'default':
            log.error('Error parsing file: node_cluster_alarms subentry ' +
                      'should be named \'default\'')
            return False
        ctx = ' under node_cluster_alarms[default]'
        # Are there some alarm key defined
        # (if not, the next line throws exception)
        c_alarms = cluster_alarms[ckeys[0]]['alarms']
        if c_alarms is None:
            log.error('Error parsing file: empty alarm list%s' % (ctx))
            return False
        # Now check validity of alarm entries
        akeys = c_alarms.keys()
        for k in akeys:
            # Must be a list
            v = c_alarms[k]
            ktype = type(v)
            if ktype is not list:
                log.error('Error parsing file: alarm entry for %s ' +
                          'is not a list (%s)'
                          % (k, ktype.__name__))
                return False
            # Each member of list must be a string
            for s in v:
                stype = type(s)
                if stype is not str:
                    log.error('Error parsing file: alarm entry for %s ' +
                              'is not a list of strings (%s) [%s]'
                              % (k, stype.__name__, s))
                    return False
        # Try to retrieve alarms definitions
        # and check for overall validity
        ctx = ''
        alarms = alarms_yaml['alarms']
        if alarms is None:
            log.error('Error parsing file: empty alarm list%s' % (ctx))
            return False
        # alarms entry should be a list
        atype = type(alarms)
        if atype is not list:
            log.error('Error parsing file: alarms entry is not a list (%s)'
                      % (atype.__name__))
            return False
        # Keep the complete list of alarm names
        anames = []
        # Checking all alarms
        for alarm in alarms:
            akeys = alarm.keys()
            if not check_alarm_entry_field(alarm, 'name', str):
                return False
            # TODO do we need to add some more checks here ?
            anames.append(alarm['name'])
        # Now check that all alarm referenced in alarm groups have been defined
        for agroup in c_alarms:
            for aname in c_alarms[agroup]:
                if aname not in anames:
                    log.error('Error parsing file: alarm with name %s ' +
                              'is not defined but is referenced in alarm ' +
                              'group %s'
                              % (aname, agroup))
                    return False
    except KeyError as e:
        log.error('Error parsing file: can not find %s key%s' % (e, ctx))
        return False
    except Exception as e:
        log.error('Error parsing file: unknown exception %s %s'
                  % (type(e), str(e)))
        return False
    return True

# Retrieve alarm by its name within list
# --------------------------------------


def find_alarm_by_name(aname, alarms):
    for alarm in alarms:
        if alarm['name'] == aname:
            return alarm
    return None

# Convert YAML file containing alarms into lua code
# and create Hindsight configuration files
# -------------------------------------------------


def yaml_alarms_2_lua_and_hindsight_cfg_files(
        lua_code_dest_dir, lua_config_dest_dir, yaml_file,
        template, cfg_template):
    log.info(
        'Converting alarm YAML file %s to LUA code in %s and configs in %s'
        % (yaml_file, lua_code_dest_dir, lua_config_dest_dir))
    try:
        # Open file and retrieve YAML structure if correctly formed
        with open(yaml_file, 'r') as in_fd:
            try:
                alarms_yaml = yaml.load(in_fd)
            except yaml.YAMLError as exc:
                log.error('Error parsing file: %s' % (exc))
                return False
        # Check overall validity of alarms definitions
        if not validate_yaml(alarms_yaml):
            log.error('Error validating alarms definitions')
            return False
        # Now retrieve the informations for config and code files generation
        cluster_alarms = alarms_yaml['node_cluster_alarms']
        afd_cluster_name = cluster_alarms.keys()[0]
        for key in cluster_alarms[afd_cluster_name]['alarms'].keys():
            # Write LUA config file
            afd_file = 'afd_node_%s_%s_alarms' % (afd_cluster_name, key)
            lua_config_dest_file = os.path.join(
                lua_config_dest_dir, "%s.cfg" % (afd_file))
            log.debug('Writing config file: %s' % lua_config_dest_file)
            with open(lua_config_dest_file, 'w') as out_fd:
                try:
                    out_fd.write(cfg_template.render(
                        afd_file=afd_file,
                        afd_cluster_name=afd_cluster_name,
                        afd_logical_name=key
                    ))
                except Exception as e:
                    log.error('Error got exception: %s' % (e))
                    return False
            # Build list of associated alarms
            alarms = []
            for aname in cluster_alarms[afd_cluster_name]['alarms'][key]:
                alarms.append(find_alarm_by_name(aname, alarms_yaml['alarms']))
            afd_file = 'afd_node_%s_%s_alarms' % (afd_cluster_name, key)
            lua_code_dest_file = os.path.join(
                lua_code_dest_dir, "%s.lua" % (afd_file))
            log.debug('Writing LUA file: %s' % lua_code_dest_file)
            # Produce LUA code file corresponding to alarm
            with open(lua_code_dest_file, 'w') as out_fd:
                try:
                    out_fd.write(template.render(alarms=alarms))
                except Exception as e:
                    log.error('Error got exception: %s' % (e))
                    return False
    except Exception as e:
        log.error('Error got exception: %s' % (e))
        return False
    return True

# Command line argument parsing
# -----------------------------


def cmd_line_args_parser():
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
        '-d', '--code-destdir',
        help='destination path for LUA plugins code files ' +
        '(default %s)' % (dflt_dest_dir),
        default=dflt_dest_dir,
        dest='code_dest_dir'
    )
    parser.add_argument(
        '-D', '--config-destdir',
        help='destination path for LUA plugins configuration ' +
        'files (default %s)' % (dflt_cfg_dest_dir),
        default=dflt_cfg_dest_dir,
        dest='config_dest_dir'
    )
    parser.add_argument(
        '-t', '--template',
        help='LUA template file (default %s)' % (dflt_template),
        default=dflt_template,
        dest='template'
    )
    parser.add_argument(
        '-T', '--config-template',
        help='LUA plugins configuration template file (default %s)' %
        (dflt_cfg_template),
        default=dflt_cfg_template,
        dest='cfg_template'
    )
    parser.add_argument(
        '-w', '--watch-path',
        help='path to watch for changes',
        required=True,
        dest='watch_path'
    )
    parser.add_argument(
        '-x', '--exit',
        help='exit program without watching filesystem changes',
        action='store_const',
        const=True, default=False,
        dest='exit'
    )
    args = parser.parse_args()
    log = logger_init(args.config)
    log.info('Watch path: %s\n\tConfig: %s\n\tTemplate: %s'
             % (args.watch_path, args.config, args.template))

    if (
            not os.path.isdir(args.watch_path) or
            not os.access(args.watch_path, os.R_OK)):
        log.error("{} not a directory or is not readable"
                  .format(args.watch_path))
        sys.exit(1)

    if (
            not os.path.isdir(args.code_dest_dir) or
            not os.access(args.code_dest_dir, os.W_OK)):
        log.error("{} not a directory or is not writable"
                  .format(args.code_dest_dir))
        sys.exit(1)

    if (
            not os.path.isdir(args.config_dest_dir) or
            not os.access(args.config_dest_dir, os.W_OK)):
        log.error("{} not a directory or is not writable"
                  .format(args.config_dest_dir))
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
        log.info('Using LUA template %s and LUA config template %s'
                 % (args.template, args.cfg_template))
        j2_env = Environment(
            loader=FileSystemLoader(
                os.path.dirname(
                    args.template)),
            trim_blocks=True)
        template = j2_env.get_template(
            os.path.basename(
                args.template))
        j2_cfg_env = Environment(
            loader=FileSystemLoader(
                os.path.dirname(
                    args.cfg_template)),
            trim_blocks=True)
        cfg_template = j2_cfg_env.get_template(
            os.path.basename(
                args.cfg_template))
        if not yaml_alarms_2_lua_and_hindsight_cfg_files(
                args.code_dest_dir,
                args.config_dest_dir,
                src,
                template,
                cfg_template
        ):
            log.error('Error converting YAML alarms into LUA code')

    # Asked to leave right away or continue watching inotify events ?
    if args.exit:
        sys.exit(0)

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

if __name__ == '__main__':
    cmd_line_args_parser()

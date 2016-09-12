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
import hashlib
import jinja2
import logging
import os
import pyinotify
import re
import sys
import yaml

# inotify dir/file watcher extension requirements
# -----------------------------------------------
from pyinotify import WatchManager, Notifier, ProcessEvent, IN_CLOSE_WRITE

# Jinja2 templating requirements
# ------------------------------
from jinja2 import Environment, FileSystemLoader

# Logging extension requirements
# ------------------------------
from logging.config import fileConfig

# Best practice code for logging
# ------------------------------
try:  # Python 2.7+
    from logging import NullHandler
except ImportError:
    class NullHandler(logging.Handler):
        def emit(self, record):
            pass

# Global variables initialization
# -------------------------------

dflt_cfg_dir = os.path.join(
    '/etc', 'stacklight', 'alarming')
dflt_config = os.path.join(
    dflt_cfg_dir, 'config', 'alarm-manager.ini')
dflt_template = os.path.join(
    dflt_cfg_dir, 'templates', 'lua_alarming_template.j2')
dflt_cfg_template = os.path.join(
    dflt_cfg_dir,
    'templates', 'alert_manager_lua_config_template.cfg.j2')
dflt_dest_dir = os.path.join(
    '/opt', 'ccp', 'lua', 'modules', 'stacklight_alarms')
dflt_cfg_dest_dir = os.path.join(
    '/var', 'lib', 'hindsight', 'load', 'analysis')
dflt_alarm_file = 'alarms.yaml'

# Logging initialization
# ----------------------


def logger_init(cfg_file):
    """Initialize logger instance."""
    log = logging.getLogger()
    log.setLevel(logging.DEBUG)
    try:
        log.debug('Looking for log configuration file: %s' % cfg_file)
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

# Class for keeping configuration parameters
# ------------------------------------------


class AlarmConfig():
    """
    Class used to store parameters
    """
    def __init__(self, code_dest_dir, config_dest_dir,
                 source_file, template, config_template):
        self._code_dest_dir = code_dest_dir
        self._config_dest_dir = config_dest_dir
        self._source_file = source_file
        self._template = template
        self._config_template = config_template
        self._sha256 = None

# Class for processing inotify events
# ------------------------------------


class InotifyEventsHandler(ProcessEvent):
    """
    Class used to process inotify events.
    """
    def my_init(self, cfg, name, out=None):
        """
        @param cfg: configuration to use for generation callback.
        @type cfg: AlarmConfig.
        @param name: File name to be watched.
        @type name: String.
        @param out: Logger where events will be written.
        @type out: Object providing a valid logging object interface.
        """
        if out is None:
            out = log
        self._out = out
        self._cfg = cfg
        self._name = name

    def process_default(self, event):
        """
        Writes event string representation to logging object provided to
        my_init().

        @param event: Event to be processed. Can be of any type of events but
                      IN_Q_OVERFLOW events (see method process_IN_Q_OVERFLOW).
        @type event: Event instance
        """
        self._out.debug(
            'Received event %s'
            % str(event))
        # File name on which inotify event has been triggered does
        # not match => return right away
        if event.name != self._name:
            self._out.debug(
                'Ignoring event %s (path does not match %s)'
                % (str(event), self._name))
            return
        self._out.info('File %s has been updated' % event.name)
        # Callback function called with proper parameters
        if not yaml_alarms_2_lua_and_hindsight_cfg_files(
                self._cfg
        ):
            log.error('Error converting YAML alarms into LUA code')

# Check alarm entry for field existence and type
# TODO: see if we ca use similar methods from
# fuel-ccp which uses jsonschema to validate types.
# -------------------------------------------------


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
# TODO: see if we ca use similar methods from
# fuel-ccp which uses jsonschema to validate types.
#
# TODO: do not return false right away
# when processing lists so that most errors
# are reported at once allowing for faster
# achievement of correctness
# -------------------------------------------------


def validate_yaml(alarms_yaml):
    log.info('Validating YAML alarms structure')
    ctx = ''
    try:
        log.debug('Retrieving all alarms')
        # Try to retrieve alarms definitions
        # and check for overall validity
        alarms = alarms_yaml['alarms']
        if alarms is None:
            log.error('Error parsing file: empty alarm list')
            return False
        # alarms entry should be a list
        atype = type(alarms)
        if atype is not list:
            log.error('Error parsing file: alarms entry is not a list (%s)'
                      % atype.__name__)
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
        log.debug('Found %d alarms' % len(anames))
        # Try to retrieve alarms groups definitions
        # and check overall validity
        log.debug('Retrieving alarms groups')
        cluster_alarms = alarms_yaml['node_cluster_alarms']
        ckeys = cluster_alarms.keys()
        for ckey in ckeys:
            log.debug('Parsing alarms group %s' % ckey)
            ctx = ' under node_cluster_alarms[%s]' % ckey
            # Are there some alarm key defined
            # (if not, the next line throws exception)
            c_alarms = cluster_alarms[ckey]['alarms']
            if c_alarms is None:
                log.error('Error parsing file: empty alarm list%s' % ctx)
                return False
            # Now check validity of alarm entries
            akeys = c_alarms.keys()
            log.debug('Found %d alarms in group %s' % (len(akeys), ckey))
            for k in akeys:
                # Must be a list
                v = c_alarms[k]
                ktype = type(v)
                if ktype is not list:
                    log.error('Error parsing file: alarm entry for %s ' +
                              'is not a list (%s)%s'
                              % (k, ktype.__name__, ctx))
                    return False
                # Each member of list must be a string
                for s in v:
                    stype = type(s)
                    if stype is not str:
                        log.error('Error parsing file: alarm entry for %s ' +
                                  'is not a list of strings (%s) [%s]%s'
                                  % (k, stype.__name__, s, ctx))
                        return False
            # Now check that all alarm referenced in
            # alarm groups have been defined
            for agroup in c_alarms:
                for aname in c_alarms[agroup]:
                    if aname not in anames:
                        log.error(
                            ('Error parsing file: alarm with name %s is not ' +
                             'defined but is referenced in alarm group %s')
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
        alarm_config):
    (lua_code_dest_dir,
     lua_config_dest_dir,
     yaml_file,
     template,
     cfg_template) = (alarm_config._code_dest_dir,
                      alarm_config._config_dest_dir,
                      alarm_config._source_file,
                      alarm_config._template,
                      alarm_config._config_template)
    log.info(
        'Converting alarm YAML file %s to LUA code in %s and configs in %s'
        % (yaml_file, lua_code_dest_dir, lua_config_dest_dir))
    try:
        if os.stat(yaml_file).st_size == 0:
                log.error('File %s will not be parsed: size = 0' % yaml_file)
                return False
        # Open file and retrieve YAML structure if correctly formed
        with open(yaml_file, 'r') as in_fd:
            try:
                alarms_defs = in_fd.read()
                sha256sum = hashlib.sha256(alarms_defs).hexdigest()
                if sha256sum == alarm_config._sha256:
                    log.warning('No change detected in file: %s' % yaml_file)
                    return True
                alarm_config._sha256 = sha256sum
                alarms_yaml = yaml.load(alarms_defs)
            except yaml.YAMLError as exc:
                log.error('Error parsing file: %s' % exc)
                return False
        # Check overall validity of alarms definitions
        if not validate_yaml(alarms_yaml):
            log.error('Error validating alarms definitions')
            return False
        # Now retrieve the information for config and code files generation
        cluster_alarms = alarms_yaml['node_cluster_alarms']
        for afd_cluster_name in cluster_alarms:
            for key in cluster_alarms[afd_cluster_name]['alarms'].keys():
                # Key can not contain dash or other non letter/numbers
                if not re.match('^[A-Za-z0-9]*$', key):
                    log.error('Alarm group name can only contain letters ' +
                              'and digits: %s'
                              % key)
                    return False
                # Write LUA config file
                afd_file = 'afd_node_%s_%s_alarms' % (afd_cluster_name, key)
                lua_config_dest_file = os.path.join(
                    lua_config_dest_dir, "%s.cfg" % afd_file)
                log.debug('Writing config file: %s' % lua_config_dest_file)
                with open(lua_config_dest_file, 'w') as out_fd:
                    try:
                        out_fd.write(cfg_template.render(
                            afd_file=afd_file,
                            afd_cluster_name=afd_cluster_name,
                            afd_logical_name=key
                        ))
                    except Exception as e:
                        log.error('Error got exception: %s' % e)
                        return False
                # Build list of associated alarms
                alarms = []
                for aname in cluster_alarms[afd_cluster_name]['alarms'][key]:
                    alarms.append(
                        find_alarm_by_name(
                            aname, alarms_yaml['alarms']))
                afd_file = 'afd_node_%s_%s_alarms' % (afd_cluster_name, key)
                lua_code_dest_file = os.path.join(
                    lua_code_dest_dir, "%s.lua" % afd_file)
                log.debug('Writing LUA file: %s' % lua_code_dest_file)
                # Produce LUA code file corresponding to alarm
                with open(lua_code_dest_file, 'w') as out_fd:
                    try:
                        out_fd.write(template.render(alarms=alarms))
                    except Exception as e:
                        log.error('Error got exception: %s' % e)
                        return False
    except Exception as e:
        log.error('Error got exception: %s' % e)
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
        % dflt_config,
        default=dflt_config,
        dest='config'
    )
    parser.add_argument(
        '-d', '--code-destdir',
        help='destination path for LUA plugins code files ' +
        '(default %s)' % dflt_dest_dir,
        default=dflt_dest_dir,
        dest='code_dest_dir'
    )
    parser.add_argument(
        '-D', '--config-destdir',
        help='destination path for LUA plugins configuration ' +
        'files (default %s)' % dflt_cfg_dest_dir,
        default=dflt_cfg_dest_dir,
        dest='config_dest_dir'
    )
    parser.add_argument(
        '-t', '--template',
        help='LUA template file (default %s)' % dflt_template,
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
        help='path to watch for changes (default %s)' %
        (dflt_cfg_dir),
        default=dflt_cfg_dir,
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
    log.info('Looking for existing readable file: %s' % src)
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
        alarm_cfg = AlarmConfig(
            args.code_dest_dir,
            args.config_dest_dir,
            src,
            template,
            cfg_template)
        if not yaml_alarms_2_lua_and_hindsight_cfg_files(
                alarm_cfg
        ):
            log.error('Error converting YAML alarms into LUA code')

    # Asked to leave right away or continue watching inotify events ?
    if args.exit:
        sys.exit(0)

    # watch manager instance
    wm = WatchManager()
    # notifier instance and init
    notifier = Notifier(
        wm,
        default_proc_fun=InotifyEventsHandler(
            cfg=alarm_cfg,
            name=dflt_alarm_file))
    # What mask to apply
    mask = IN_CLOSE_WRITE
    log.debug('Start monitoring of %s' % args.watch_path)
    # Do not recursively dive into path
    # Do not add watches on newly created subdir in path
    # Do not do globbing on path name
    wm.add_watch(args.watch_path,
                 mask, rec=False,
                 auto_add=False,
                 do_glob=False)
    # Loop forever (until sigint signal get caught)
    notifier.loop(callback=None)

if __name__ == '__main__':
    cmd_line_args_parser()

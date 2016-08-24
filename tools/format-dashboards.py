#!/usr/bin/python3
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

import argparse
import sys
import glob
import os
import json


class Action(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        path = values
        if os.path.isdir(path):
            path = "{}/*.json".format(path)
        elif os.path.isfile(path):
            pass
        else:
            raise ValueError("'{}' no such file or directory".format(path))
        setattr(namespace, self.dest, path)


parser = argparse.ArgumentParser(
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description="""
Format JSON file with ordered keys
Remove sections:
    templating.list[].current
    templating.list[].options
Override time entry to {{"from": "now-1h","to": "now"}}
Enable sharedCrosshair
Increment the version

WARNING: this script modifies all manipulated files.

if a DIRECTORY is provided, all files with suffix '.json' will be modified.

WARNING: this script modifies all manipulated files.""")
parser.add_argument('path',
                    action=Action,
                    help="Path to JSON file or directory "
                         "including .json files")
path = parser.parse_args().path

for f in glob.glob(path):
    print('Processing {}...'.format(f))
    data = None
    absf = os.path.abspath(f)
    with open(absf) as _in:
        data = json.load(_in)
    dashboard = data.get('dashboard')
    if not dashboard:
        print('Malformed JSON: no "dashboard" key')
        sys.exit(1)
    for k, v in dashboard.items():
        if k == 'annotations':
            for anno in v.get('list', []):
                anno['datasource'] = 'CCP InfluxDB'
        if k == 'templating':
            variables = v.get('list', [])
            for o in variables:
                if o['type'] == 'query':
                    o['options'] = []
                    o['current'] = {}
                    o['refresh'] = 1

    dashboard['time'] = {'from': 'now-1h', 'to': 'now'}
    dashboard['sharedCrosshair'] = True
    dashboard['refresh'] = '1m'
    dashboard['id'] = None
    dashboard['version'] = dashboard.get('version', 0) + 1

    with open(absf, 'w') as out:
        json.dump(data, out, indent=2, sort_keys=True)

    print('Done processing {}.'.format(f))

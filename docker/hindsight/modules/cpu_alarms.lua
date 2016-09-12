local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local alarms = {
  {
    ['name'] = 'cpu-critical',
    ['description'] = 'The CPU usage is too high',
    ['severity'] = 'critical',
    ['trigger'] = {
      ['logical_operator'] = 'or',
      ['rules'] = {
        {
          ['metric'] = 'intel.procfs.cpu.idle_percentage',
          ['fields'] = {
              ['cpuID'] = 'all'
          },
          ['relational_operator'] = '<=',
          ['threshold'] = '5',
          ['window'] = '120',
          ['periods'] = '0',
          ['function'] = 'avg',
        },
        {
          ['metric'] = 'intel.procfs.cpu.iowait_percentage',
          ['fields'] = {
              ['cpuID'] = 'all'
          },
          ['relational_operator'] = '>=',
          ['threshold'] = '35',
          ['window'] = '120',
          ['periods'] = '0',
          ['function'] = 'avg',
        },
      },
    },
  },
  {
    ['name'] = 'cpu-warning',
    ['description'] = 'The CPU usage is high',
    ['severity'] = 'warning',
    ['trigger'] = {
      ['logical_operator'] = 'or',
      ['rules'] = {
        {
          ['metric'] = 'intel.procfs.cpu.idle_percentage',
          ['fields'] = {
              ['cpuID'] = 'all'
          },
          ['relational_operator'] = '<=',
          ['threshold'] = '15',
          ['window'] = '120',
          ['periods'] = '0',
          ['function'] = 'avg',
        },
        {
          ['metric'] = 'intel.procfs.cpu.iowait_percentage',
          ['fields'] = {
              ['cpuID'] = 'all'
          },
          ['relational_operator'] = '>=',
          ['threshold'] = '25',
          ['window'] = '120',
          ['periods'] = '0',
          ['function'] = 'avg',
        },
      },
    },
  },
}

return alarms

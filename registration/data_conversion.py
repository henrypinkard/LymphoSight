from pymaricumpiler import convert
import os
import csv
import numpy as np
from pathlib import Path
import sys
import argparse

#parse command line arguments
parser = argparse.ArgumentParser()
parser.add_argument('--stack', action='store_true')
parser.add_argument('--stitch', action='store_true')
parser.add_argument('--export', action='store_true')
parser.add_argument('--time_reg', action='store_true')
parser.add_argument('--no_param_load', action='store_true')
parser.add_argument('--rereg_z', action='store_true')
parser.add_argument('--stack_lr', type=float, default=1.0)
parser.add_argument('--stack_reg', type=float, default=1e-2)
parser.add_argument('--stitch_reg_xy', type=float, default=0.004)
parser.add_argument('--stitch_reg_z', type=float, default=0.0001)
parser.add_argument('--ids', type=str, nargs='*')

parser.add_argument('--af_reg_channels', type=int, nargs='*', default=[1,4])
parser.add_argument('--extra_reg_channels', type=int, nargs='*', default=[])
parser.add_argument('--z_reg_channels', type=int, nargs='*', default=[0])

parser.add_argument('--max_tp', type=int, default=-1)
parser.add_argument('--min_tp', type=int, default=-1)
parser.add_argument('--suffix', type=str, default='')
parser.add_argument('--param_cache', type=str, default='optimized_params')
args = parser.parse_args()


if len(sys.argv) == 1:
    print('OVERRIDING THE DEFULAT ARGS!!!! ARE YOU SURE YOU WNAT THIS????\n\nHENRY!!\nARE YOU SURE?!?!')
    args = parser.parse_args(['--ids', '46', '--export', '--suffix', 'center_z_stitch_newnewsigns'])

print('Got arguments:')
print(args)

home = str(Path.home())

storage_path = home + '/lymphosight_data/'


imaris_dir = storage_path + 'imaris_files'
raw_data_dir = storage_path + 'raw_data/'
param_cache_dir = storage_path + args.param_cache + '/'
log_dir = storage_path + 'conversion_log/'
#make sure they all exist
# for p in [imaris_dir, raw_data_dir, param_cache_dir, log_dir]:
#     if not os.path.exists(p):
#         os.makedirs(p)

data_list = home + '/GitRepos/LymphoSight/LymphosightDatasets.csv'

with open(data_list, 'r') as f:
    reader = csv.DictReader(f)
    experiments = list(reader)
    column_names = reader.fieldnames

def get_dataset_path(ID):
    ex = [e for e in experiments if e['ID'] == ID][0]
    path = '{} {}{}{}'.format(ex['Date'], ex['Folder'], os.sep, ex['Experiment'])
    return path

def get_value(ID, key):
    ex = [e for e in experiments if e['ID'] == ID][0]
    return ex[key]

if len(args.ids) == 0:
    print('no ids arg, usign all')
    ids = [e['ID'] for e in experiments]
else:
    ids = args.ids
#convert all with no corrections
for ID in ids:

    data_path = get_dataset_path(ID)
    magellan_dir = raw_data_dir + data_path

    print('\nconverting ID: {} \t {}\n'.format(ID, magellan_dir))
    # isr_ch = [int(v) for v in get_value(ID, 'ISR ch').split('+')]

    # af_reg_channels = [int(v) for v in get_value(ID, 'af reg channels').split('+')]
    extra_reg_channels = [int(v) for v in get_value(ID, 'extra_reg_channels').split('+') if v != '']

    if (args.max_tp != -1):
        print('capping max_tp at: {}'.format(args.max_tp))
        max_tp = args.max_tp
    else:
        max_tp = int(get_value(ID, 'Usable frames'))

    if (args.min_tp != -1):
        print('capping min_tp at: {}'.format(args.min_tp))
        min_tp = args.min_tp
    else:
        min_tp = 0


    x_corr_xy_channels = [args.af_reg_channels]
    if len(args.extra_reg_channels) > 0:
        x_corr_xy_channels += args.extra_reg_channels
    z_reg_channels = [args.z_reg_channels]
    stitch_channels = [args.af_reg_channels, args.z_reg_channels[0]]
    if len(args.extra_reg_channels) > 0:
        stitch_channels += args.extra_reg_channels


    # print(x_corr_xy_channels)
    # print(z_reg_channels)
    # print(stitch_channels)

    convert(magellan_dir,
            input_filter_sigma=2,
            output_dir=imaris_dir,
            output_basename=ID,
            intra_stack_registration_channels=[1, 2, 3, 4, 5],
            reverse_rank_filter=True,
            param_cache_dir=param_cache_dir,
            log_dir=log_dir,
            min_tp=min_tp,
            max_tp=max_tp,
            suffix=args.suffix,
            stack_learning_rate=args.stack_lr,
            stack_reg=args.stack_reg,

            time_reg_channels=x_corr_xy_channels, 
            stitch_channels=stitch_channels, 
            time_reg_z_channels = z_reg_channels,


            stitch_method='optimize',
            stitch_downsample_factor_xy=2,
            stitch_regularization_xy=args.stitch_reg_xy,
            stitch_regularization_z=args.stitch_reg_z,
            stack=args.stack,
            stitch=args.stitch,
            time_reg=args.time_reg,
            export=args.export,
            rereg_z=args.rereg_z,
            load_params=not args.no_param_load)

from pymaricumpiler import convert
import os
import csv
import numpy as np
from pygellan import MagellanDataset

#download latest version of the master data spreadsheet
os.system("rclone copy wallercloud:henry/lymphosight/Datasets.csv .")

with open('Datasets.csv', 'r') as f:
  reader = csv.reader(f)
  list_form = list(reader)
str_array = np.array(list_form[1:])
data_indices = str_array[:, 0].astype(np.int)

def get_dataset_path(index):
    dat_list_index = int((data_indices == index).nonzero()[0])
    date = str_array[dat_list_index, 1]
    experiment = str_array[dat_list_index, 2]
    dataset = str_array[dat_list_index, 3]
    path = '{} {}{}{}'.format(date, experiment, os.sep, dataset)
    return path

#list metadata
# for index in data_indices:
#     try:
#         magellan_dir = '/media/hugespace/henry/data/lymphosight/raw_data/' + get_dataset_path(index)
#         magellan = MagellanDataset(magellan_dir)
#         #find indices for the first image to read time metadata
#         channel = 0
#         position = list(magellan.p_t_z_c_tree.keys())[0]
#         z = list(magellan.p_t_z_c_tree[position][channel].keys())[0]
#         frame = 0
#         image, metadata =magellan.read_image(channel_index=channel, z_index=z,
#                                              t_index=frame, pos_index=position, read_metadata=True)
#         time = metadata['Time'][1 +metadata['Time'].find(' '): -2]
#         frames = magellan.get_num_frames()
#         positions = magellan.get_num_xy_positions()
#         min_z, max_z = magellan.get_min_max_z_index()
#         z_size = max_z - min_z
#         print('{},{},{},{}'.format(time, frames, positions, z_size))
#     except:
#         print('error')


magellan_dir = '/media/hugespace/henry/data/lymphosight/raw_data/' + get_dataset_path(36)
imaris_dir = '/media/hugespace/henry/data/lymphosight/imaris_files'
imaris_name = 'no correction conversion test'

convert(magellan_dir, do_intra_stack=False, do_inter_stack=False, do_timepoints=False,
            output_dir=imaris_dir, output_basename=imaris_name, intra_stack_registration_channels=[1, 2, 3, 4, 5],
            intra_stack_noise_model_sigma=2, intra_stack_zero_center_sigma=3,
            intra_stack_likelihood_threshold_smooth=1.0, intra_stack_likelihood_threshold=-18,
            inter_stack_registration_channel=0, inter_stack_max_z=7, timepoint_registration_channel=0, n_cores=24)
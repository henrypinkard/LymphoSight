from imariswriter import ImarisJavaWrapper
import numpy as np
from stitcher import stitch_single_channel
from data_reading import read_raw_data


def write_imaris(directory, name, time_series, pixel_size_xy_um, pixel_size_z_um):
    timepoint0 = time_series[0][0]
    num_channels = len(timepoint0)
    t0c0 = timepoint0[0]
    imaris_size_x = t0c0.shape[2]
    imaris_size_y = t0c0.shape[1]
    imaris_size_z = t0c0.shape[0]
    num_frames = len(time_series)
    byte_depth = 1 if t0c0.dtype == np.uint8 else 2

    with ImarisJavaWrapper(directory, name, (imaris_size_x, imaris_size_y, imaris_size_z), byte_depth, num_channels,
                           num_frames, pixel_size_xy_um, float(pixel_size_z_um)) as writer:
        for time_index, (timepoint, elapsed_time_ms) in enumerate(time_series):
            for channel_index in range(len(timepoint)):
                stack = timepoint[channel_index]
                for z_index, image in enumerate(stack):
                    image = image.astype(np.uint8 if byte_depth == 1 else np.uint16)
                    #add image to imaris writer
                    print('Frame: {} of {}, Channel: {} of {}, Slice: {} of {}'.format(
                        time_index+1, num_frames, channel_index+1, num_channels, z_index, imaris_size_z))
                    writer.write_z_slice(image, z_index, channel_index, time_index, elapsed_time_ms)
    print('Finshed!')

def ram_efficient_stitch_register_imaris_write(directory, name, imaris_size, magellan, metadata,
                    registration_series, translation_series, abs_timepoint_registrations, input_filter_sigma=None,
                                               reverse_rank_filter=False):
    num_channels = metadata['num_channels']
    num_frames = metadata['num_frames']
    byte_depth = metadata['byte_depth']
    print('Imaris file: {}'.format(name))
    print('Imaris directory: {}'.format(directory))
    with ImarisJavaWrapper(directory, name, (int(imaris_size[2]), int(imaris_size[1]), int(imaris_size[0])), byte_depth,
                num_channels, num_frames, metadata['pixel_size_xy_um'], float(metadata['pixel_size_z_um'])) as writer:
        for time_index in range(num_frames):
            print('Frame {}'.format(time_index))
            raw_stacks, nonempty_pixels, timestamp = read_raw_data(magellan, metadata, time_index=time_index,
                                    reverse_rank_filter=reverse_rank_filter, input_filter_sigma=input_filter_sigma)
            for channel_index in range(num_channels):
                stitched = stitch_single_channel(raw_stacks, translations=translation_series[time_index],
                        registrations=registration_series[time_index], tile_overlap=metadata['tile_overlaps'],
                        row_col_coords=metadata['row_col_coords'], channel_index=channel_index)
                #fit into the larger image to account for timepoint registrations
                tp_registered = np.zeros(imaris_size)
                tp_registered[abs_timepoint_registrations[time_index, 0]:abs_timepoint_registrations[time_index, 0] + stitched.shape[0],
                        abs_timepoint_registrations[time_index, 1]:abs_timepoint_registrations[time_index, 1] + stitched.shape[1],
                       abs_timepoint_registrations[time_index, 2]:abs_timepoint_registrations[time_index, 2] + stitched.shape[2]] = stitched
                print('writing to Imaris channel {}'.format(channel_index))
                for z_index, image in enumerate(tp_registered):
                    image = image.astype(np.uint8 if byte_depth == 1 else np.uint16)
                    # add image to imaris writer
                    # print('Frame: {} of {}, Channel: {} of {}, Slice: {} of {}'.format(
                    #     time_index + 1, num_frames, channel_index + 1, num_channels, z_index, imaris_size[0]))
                    writer.write_z_slice(image, z_index, channel_index, time_index, timestamp)
    print('Finshed!')

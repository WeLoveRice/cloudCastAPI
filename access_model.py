import xarray as xr
import json
import os
import time
import re
import glob


def open_var_model(model_dir: str):
    model_files = glob.glob(model_dir)
    for model_file in model_files:
        if model_file.endswith(".idx"):
            os.remove(os.path.join(model_dir, model_file))
    model = xr.open_mfdataset(model_dir, engine='cfgrib', combine='nested', concat_dim='time', coords='different')
    if 'heightAboveGround' in model.coords:
        model = model.reset_coords(names='heightAboveGround', drop=True)
    model = model.set_index(time='valid_time')
    return model


def open_all_models(model_dir: str):
    model_files = os.listdir(model_dir)
    var_list = set([re.findall(r'^[^\.]+\.', file_name)[0] for file_name in model_files])
    models = [open_var_model(f'{model_dir}{var}*') for var in var_list]
    return models


def forecast_at_location(model, latitude, longitude):
    ds_location = model.sel(longitude=longitude, latitude=latitude, method="nearest")
    df_location = ds_location.to_dataframe()
    df_location = df_location[['tcc', 't2m', 'aptmp', 'r2', 'u10', 'v10']]
    df_location['time'] = df_location.index
    df_location = df_location.rename(
        columns={
            'time':'timestamp', 
            'tcc':'total_cloud_cover', 
            't2m':'temp',
            'aptmp':'feels_like',
            'r2': 'relative_humidity',
            'u10': 'u-wind',
            'v10': 'v-wind'
            })
    df_location = df_location.reset_index(drop=True)
    forecast_json = df_location.to_json(orient='records')
    forecast_json = {
        'type': 'Feature',
        'geometry': {
            'type': 'Point',
            'coordinates': {
                'latitude': latitude,
                'longitude': longitude
            }
        },
        'properties': {
            'meta': {
                'units': {
                    'timestamp': 'UNIX timestamp',
                    'total_cloud_cover': '%',
                    'temp': 'K',
                    'feels_like': 'K',
                    'relative_humidity': '%',
                    'u-wind': 'm/s',
                    'v-wind': 'm/s'
                }
            }
        },
        'timeseries':json.loads(forecast_json)
    }
    forecast_json = json.dumps(forecast_json)
    return forecast_json

def test_forecast(model):
    import numpy as np
    coord_array = np.array(np.meshgrid(range(-90,90),range(-180,180))).T.reshape(-1,2)
    timeseries_function_call = []
    for lat, lon in coord_array:
        start = time.perf_counter()
        test = forecast_at_location(model=model, latitude=int(lat), longitude=int(lon))
        end = time.perf_counter()
        time_taken = end - start
        timeseries_function_call.append(time_taken)
    print(f'Average: {np.average(timeseries_function_call)}')
    print(f'Max: {max(timeseries_function_call)}')
    print(f'Min: {min(timeseries_function_call)}')



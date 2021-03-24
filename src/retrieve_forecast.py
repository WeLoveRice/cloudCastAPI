import xarray as xr
import json
import pandas as pd
import numpy as np
from dask import compute, delayed
from math import floor
import cfgrib
# cfgrib.open_datasets('noaa_model/gfs.t12z.pgrb2.0p25.f020')

def load_datasets_from_model() -> xr.Dataset:
    var_list = [
        ':TCDC:entire atmosphere',
        ':TMP:2 m ',
        ':RH:2 m ',
        ':APTMP:2 m ',
        ':UGRD:10 m ',
        ':VGRD:10 m '
    ]

    delayed_dds_list = []

    for var in var_list:
        ext_str = var.replace(':', '_').replace(' ', '_')
        ds_var = delayed(xr.open_mfdataset)(
            f'./noaa_model/*.{ext_str}', 
            engine='cfgrib', 
            combine='nested',
            concat_dim='time'
        )
        delayed_dds_list.append(ds_var)
    dds_list = compute(*delayed_dds_list)

    return dds_list


def forecast_at_location(ds_list_model, latitude, longitude): 
    delayed_ds_location_list = []

    for ds_model in ds_list_model:
        ds_location = delayed(ds_model.sel)(longitude=longitude, latitude=latitude, method="nearest")
        delayed_ds_location_list.append(ds_location)
    
    ds_location_list = compute(*delayed_ds_location_list)

    df_location_list = []
    for ds_location in ds_location_list:
        df_location = ds_location.to_dataframe()
        df_location_list.append(df_location)
    
    df_forecast = pd.concat(df_location_list, axis=1).T.drop_duplicates().T
    df_forecast = df_forecast[['valid_time', 'tcc', 't2m', 'aptmp', 'r2', 'u10', 'v10']]
    df_forecast['wind_speed'] = [np.sqrt(np.square(df_forecast['u10'][i])+np.square(df_forecast['v10'][i])) for i in range(0, len(df_forecast['u10']))]
    df_forecast['wind_direction'] = [(270-np.rad2deg(np.arctan2(df_forecast['v10'][i],df_forecast['u10'][i])))%360 for i in range(0, len(df_forecast['u10']))]
    direction_list = ["N","NNE","NE","ENE","E","ESE", "SE","SSE","S","SSW","SW","WSW", "W","WNW","NW","NNW","N"]
    df_forecast['wind_direction'] = [direction_list[floor((direction_value + 11.25) / 22.5)] for direction_value in df_forecast['wind_direction']]
    df_forecast = df_forecast.drop(columns=['u10', 'v10'])
    df_forecast = df_forecast.rename(columns={'valid_time':'timestamp', 'tcc':'total_cloud_cover', 't2m':'temp', 'r2':'relative_humidity', 'aptmp':'temp_feels_like'})
    df_forecast = df_forecast.reset_index(drop=True)
    cols = ['total_cloud_cover', 'temp', 'temp_feels_like', 'relative_humidity', 'wind_speed']
    df_forecast[cols] = df_forecast[cols].apply(pd.to_numeric)
    print(df_forecast)
    df_forecast[cols] = df_forecast[cols].round(2)
    print(df_forecast)
    forecast_json = df_forecast.to_json(orient='records')

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
                    'temp_feels_like': 'K',
                    'relative_humidity': '%',
                    'wind_speed': 'm/s',
                    'wind_direction': 'compass direction'

                }
            }
        },
        'timeseries':json.loads(forecast_json)
    }
    forecast_json = json.dumps(forecast_json)
    return forecast_json

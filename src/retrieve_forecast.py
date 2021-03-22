import xarray as xr
import json
def load_current_model():
    global current_model
    current_model = xr.open_mfdataset('/noaa_model/*', engine='cfgrib', combine='nested', concat_dim='time')

def forecast_at_location(model, latitude, longitude):
    ds_location = model.sel(longitude=longitude, latitude=latitude, method="nearest")
    df_location = ds_location.to_dataframe()
    df_location = df_location[['valid_time', 'tcc', 't']]
    df_location = df_location.rename(columns={'valid_time':'timestamp', 'tcc':'total_cloud_cover', 't':'temp'})
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
                    'temp': 'K'
                }
            }
        },
        'timeseries':json.loads(forecast_json)
    }
    forecast_json = json.dumps(forecast_json)
    return forecast_json

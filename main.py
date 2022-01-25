from refresh_model import download_data
from access_model import open_all_models, test_forecast
from datetime import datetime
import xarray as xr
import zarr 
import json
model_dir = '/home/jomcgi/cloudCastAPI/noaa_files/'
weather_vars = [
        ':TCDC:entire atmosphere',
        ':TMP:2 m ',
        ':RH:2 m ',
        ':APTMP:2 m ',
        ':UGRD:10 m ',
        ':VGRD:10 m '
    ]

# download_data(noaa_vars=weather_vars)

# noaa_model = open_all_models(model_dir=model_dir)
# noaa_model = xr.merge(noaa_model)
# noaa_model = xr.merge(noaa_model, compat='override', combine_attrs='override')
# noaa_model = noaa_model.where(noaa_model.time < )
# noaa_model.to_netcdf(path='model')
noaa_model = xr.open_dataset('model', decode_times=False)
lat_min=49.959999905
lat_max=58.6350001085
lon_min=-7.57216793459
lon_max=1.68153079591
ds_uk = noaa_model.sel(longitude=(noaa_model.longitude >= lon_min) | (noaa_model.longitude <= lon_max), latitude=(noaa_model.latitude >= lat_min) | (noaa_model.latitude <= lat_max))
noaa_model = noaa_model.drop(labels=['step', 'atmosphere'], errors='ignore').load()
mask_lat = (noaa_model.latitude >= lat_min) & (noaa_model.latitude <= lat_max)
mask_lon = (noaa_model.latitude >= lon_min) & (noaa_model.latitude <= lon_max)
ds_uk.load()
ds_uk = noaa_model.where(mask_lon & mask_lat, drop=True)
ds_location = noaa_model.sel(latitude=54, longitude=22, method="nearest")
json.dumps(ds_location.to_dict())
df_location = ds_location.to_dataframe()
test_forecast(noaa_model)
noaa_model.to_zarr('temp.zarr')
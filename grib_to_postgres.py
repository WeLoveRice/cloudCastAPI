import xarray as xr
import time
var_list = [
    ':TCDC:entire atmosphere',
    ':TMP:2 m ',
    ':RH:2 m ',
    ':APTMP:2 m ',
    ':UGRD:10 m ',
    ':VGRD:10 m '
]


tic = time.perf_counter()
  
for var in var_list:
    ext_str = var.replace(':', '_').replace(' ', '_')
    ds_var = xr.open_mfdataset(
        f'./noaa_model/*.{ext_str}', 
        engine='cfgrib', 
        combine='nested',
        concat_dim='time'
    )
    ds_var.to_dataframe().to_csv(f'./noaa_model/{var}.csv')

toc = time.perf_counter()
print(f"time taken to convert datasets to csvs - {toc - tic:0.4f} seconds")
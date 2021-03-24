from src.download_model import update_model_loop, update_local_files, noaa_url_list
from src.retrieve_forecast import load_datasets_from_model, forecast_at_location
from fastapi import FastAPI
global current_model

# update_local_files(noaa_url_list())
ds_list = load_datasets_from_model()

print('testing forecast call')
print(forecast_at_location(
        ds_list_model=ds_list,
        latitude=52,
        longitude=25))

# print('done')
print('a')
# app = FastAPI()

# @app.get("/forecast/lat={latitude}&lon={longitude}")
# async def read_item(latitude: float, longitude: float):
#     return forecast_at_location(
#         model=current_model,
#         latitude=latitude,
#         longitude=longitude)
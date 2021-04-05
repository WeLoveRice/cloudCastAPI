from src.download_model import update_model_loop, update_local_files, noaa_url_list
from src.retrieve_forecast import load_datasets_from_model, forecast_at_location
from fastapi import FastAPI
import time
global current_model
update_local_files(noaa_url_list())
ds_list = load_datasets_from_model()
app = FastAPI()


@app.get("/forecast/")
async def return_forecast(lat: float, lon: float):
    tic = time.perf_counter()
    json_response = forecast_at_location(
        ds_list_model=ds_list,
        latitude=lat,
        longitude=lon)    
    toc = time.perf_counter()
    print(f"response time taken - {toc - tic:0.4f} seconds")

    return json_response

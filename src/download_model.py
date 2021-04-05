from src.retrieve_forecast import load_datasets_from_model
import re
import requests
import time
from datetime import datetime
from multiprocessing.pool import ThreadPool
from pathlib import Path
import os


def noaa_url_list():
    url = 'https://nomads.ncep.noaa.gov/pub/data/nccf/com/gfs/prod/'
    res = requests.get(url)
    pattern = re.compile(r"gfs.20[0-9]{6}")
    dir_list = pattern.findall(res.text)
    dir_list = [x.replace('gfs.', '') for x in dir_list]
    url = f'{url}gfs.{max(dir_list)}/'
    res = requests.get(url)
    pattern = re.compile(r"[0612]{2}/")
    dir_list = pattern.findall(res.text)
    dir_list = [x.replace('/', '') for x in dir_list]
    url = f'{url}{max(dir_list)}/'
    res = requests.get(url)
    if 'atmos/' in res.text:
        url = f'{url}atmos/'
        res = requests.get(url)
    pattern = re.compile(r'gfs.[^">]+\.pgrb2\.0p25\.f[0-9]{3}')
    file_list = pattern.findall(res.text)
    file_list = list(set(file_list))
    url_list = [f'{url}{file_name}' for file_name in file_list]
    return url_list[0:5]


def download_cloudcast(url: str):

    var_list = [
        ':TCDC:entire atmosphere',
        ':TMP:2 m ',
        ':RH:2 m ',
        ':APTMP:2 m ',
        ':UGRD:10 m ',
        ':VGRD:10 m '
    ]

    index = requests.get(f'{url}.idx')

    def get_byte_range(index, variable) -> str:
        pattern = re.compile(r':[0-9]+:d=.+' + variable + '.+hour fcst.+\n[0-9]{1,3}:[0-9]+:')
        range_match = pattern.findall(index.text)
        if len(range_match) == 0: return None
        pattern = re.compile(r':[0-9]+:')
        range_match = pattern.findall(range_match[0])
        range_list = [int(item.replace(':', '')) for item in range_match]
        range_str = f'{range_list[0]}-{range_list[1]}'
        return range_str

    for var in var_list:
        range_header = get_byte_range(index, var)
        if range_header is None: continue
        file_name_start_pos = url.rfind("/") + 1
        ext_str = var.replace(':', '_').replace(' ', '_')
        file_name = f'noaa_model/{url[file_name_start_pos:]}.{ext_str}'
        headers = {
            'Range': f'bytes={range_header}'
        }
        r = requests.get(url, headers=headers)
        if r.status_code in [200, 206]:
            with open(file_name, 'wb') as f:
                for data in r:
                    f.write(data)
    return url

def update_local_files(url_list):
    if not os.path.exists("./noaa_model"):
        os.makedirs("./noaa_model")
    [f.unlink() for f in Path("./noaa_model").glob("*") if f.is_file()]
    results = ThreadPool(100).imap_unordered(download_cloudcast, url_list)
    for r in results:
        print(r)

    var_list = [
        ':TCDC:entire atmosphere',
        ':TMP:2 m ',
        ':RH:2 m ',
        ':APTMP:2 m ',
        ':UGRD:10 m ',
        ':VGRD:10 m '
    ]

    for var in var_list:
        var_str = var.replace(':', '_').replace(' ', '_')
        os.system(f"cat ./noaa_model/*.{var_str} >> ./noaa_model/gfs.pgrb2.0p25.{var_str}")

    os.system('rm -r ./noaa_model/gfs.t*')
    

def update_model_loop():
    global current_model
    while True:
        current_list = noaa_url_list()
        new_list = current_list
        while current_list == new_list:
            minutesToSleep = 15 - datetime.datetime.now().minute % 15
            time.sleep(minutesToSleep * 60)
            new_list = noaa_url_list()
        update_local_files(new_list)
        current_model = load_current_model()

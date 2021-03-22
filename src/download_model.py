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
    pattern = re.compile(r'gfs.[^">]+\.pgrb2\.0p25\.f[0-9]{3}')
    file_list = pattern.findall(res.text)
    file_list = list(set(file_list))
    url_list = [f'{url}{file_name}' for file_name in file_list]
    return url_list


def download_cloudcast(url: str):
    def get_byte_ranges(url: str, variable_list: list) -> str:
        index = requests.get(f'{url}.idx')
        pattern_list = [
            re.compile(r'[0-9]{1,3}:[0-9]+.+\n[0-9]{1,3}:[0-9]+:d=[0-9]{10}:' + variable + ':[a-z]')
            for variable in variable_list
        ]
        ranges_list = [pattern.findall(index.text) for pattern in pattern_list]
        ranges_list = [item for sublist in ranges_list for item in sublist]
        pattern = re.compile(r':[0-9]+:')
        range_list = [pattern.findall(x) for x in ranges_list]
        range_list = [int(item.replace(':', '')) for sublist in range_list for item in sublist]
        range_list = sorted(range_list)
        range_list = [range_list[i * 2:(i + 1) * 2] for i in range((len(range_list) + 2 - 1) // 2)]

        range_list = [f'{int(ranges[0])}-{ranges[1]}' for ranges in range_list]
        range_str = ",".join(range_list)
        return range_str
    range_header = get_byte_ranges(url, ['TCDC'])
    file_name_start_pos = url.rfind("/") + 1
    file_name = f'noaa_model/{url[file_name_start_pos:]}'
    headers = {
        'Range': f'bytes={range_header}'
    }
    r = requests.get(url, headers=headers)
    if r.status_code == 206:
        with open(file_name, 'wb') as f:
            for data in r:
                f.write(data)
    return url

def update_local_files(url_list):
    if not os.path.exists("/noaa_model"):
        os.makedirs("/noaa_model")
    [f.unlink() for f in Path("/noaa_model").glob("*") if f.is_file()]
    results = ThreadPool(100).imap_unordered(download_cloudcast, url_list)
    for r in results:
        print(r)

def update_model_loop():
    while True:
        current_list = noaa_url_list()
        new_list = current_list
        while current_list == new_list:
            minutesToSleep = 15 - datetime.datetime.now().minute % 15
            time.sleep(minutesToSleep * 60)
            new_list = noaa_url_list()
        update_local_files(new_list)

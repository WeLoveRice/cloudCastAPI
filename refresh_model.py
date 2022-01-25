import re
import requests
import os

def noaa_url_list() -> list:
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
    return url_list


def create_curl_commands(url: str, var_list: list) -> None:
    def get_byte_range(index, variable) -> str:
        pattern = re.compile(r':[0-9]+:d=.+' + variable + '.+hour fcst.+\n[0-9]{1,3}:[0-9]+:')
        range_match = pattern.findall(index.text)
        if len(range_match) == 0: return None
        pattern = re.compile(r':[0-9]+:')
        range_match = pattern.findall(range_match[0])
        range_list = [int(item.replace(':', '')) for item in range_match]
        range_str = f'{range_list[0]}-{range_list[1]}'
        return range_str


    index = requests.get(f'{url}.idx')
    curl_commands = [
        f'curl {url} -r {get_byte_range(index, var)} -o noaa_model/{url[url.rfind("/") + 1:]}.{var.replace(":", "_").replace(" ", "_")}'
        for var in var_list
    ]
    return curl_commands


def download_data(noaa_vars: list) -> None:
    noaa_urls = noaa_url_list()
    if not os.path.exists("./noaa_model"):
        os.makedirs("./noaa_model")
    else:
        os.system('rm -r ./noaa_model/*')
    curl_commands = [create_curl_commands(url, noaa_vars) for url in noaa_urls]
    curl_commands = [item for sublist in curl_commands for item in sublist if "None" not in item]
    with open('curl_commands.txt', mode='wt', encoding='utf-8') as myfile:
        myfile.write('\n'.join(curl_commands))
    download_files_in_parallel = 'parallel --jobs 0 < curl_commands.txt'
    os.system(download_files_in_parallel)
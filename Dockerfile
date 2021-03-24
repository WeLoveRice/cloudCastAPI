FROM python:3.8-buster

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    & sudo apt-get install libeccodes0

COPY . .

CMD [ "python", "main.py" ]
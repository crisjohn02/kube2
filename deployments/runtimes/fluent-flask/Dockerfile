# start by pulling the python image
FROM python:3.10

# copy the requirements file into the image
COPY ./requirements.txt /requirements.txt


# install the dependencies and packages in the requirements file
RUN pip install -r requirements.txt

RUN apt-get update && apt-get install -y curl
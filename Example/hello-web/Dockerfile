FROM docker.io/library/python:3.13-alpine
WORKDIR /site
COPY index.html .
EXPOSE 8000
CMD ["python3", "-m", "http.server", "8000", "--bind", "0.0.0.0"]
FROM golang:1.17.8-alpine3.15
WORKDIR /build
RUN apk update
RUN apk add --update --no-cache nodejs npm git make python3 gcc musl-dev linux-headers bash
RUN npm i -g yarn
ADD ./package.json /build/package.json
RUN yarn || true
ADD . /build
RUN yarn compile
RUN go build -o /build/create-genesis ./
ENTRYPOINT ["/build/create-genesis"]
# build stage
FROM golang:alpine as backend-builder
RUN apk --no-cache add ca-certificates
ENV GO111MODULE=on
WORKDIR /app
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build 

# final stage
FROM alpine
COPY --from=backend-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=backend-builder /app/regolancer /app/


RUN apk add --no-cache bash
WORKDIR /app


ENTRYPOINT [ "./regolancer" ]

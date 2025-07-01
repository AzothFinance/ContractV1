## Azoth Contract V1
### Prerequisites
1. [Node.js](https://nodejs.org/en/download)  
2. [Foundry](https://getfoundry.sh/introduction/installation)

```shell
$ curl -L https://foundry.paradigm.xyz | bash
$ foundryup
```

### Install

```shell
$ forge install
$ npm install
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test -vvv
```

### Deploy

```shell
$ cp .env.copy .env
# Configure the required environment for .env

$ node script/deploy.js
```

### Help

```shell
$ forge --help
```

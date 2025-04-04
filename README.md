# tflite2cpp

Research and implementation notes on porting TensorFlow Lite models to C++ for efficient inference

---

## Types of IR in TVM

| Level             | IR Name                  | Description                                                                                                                                   |
|------------------|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| High-level        | Relay                    | A functional programming-based IR representing neural networks; used for optimizations like operator fusion, layout transforms, etc.          |
| Mid-level         | Tensor Expression (TE)   | Describes how a computation should be computed using loops and indexing (algorithm + schedule). It is more low-level than Relay.              |
| Low-level         | TIR (Tensor IR)          | TVM’s imperative IR that represents lowered loops, memory accesses, and hardware-level parallelism (e.g., threads).                           |
| Hardware-specific | CodeGen IRs              | These are representations targeting CUDA, Metal, LLVM IR, etc. They are used during code generation for specific backends.                    |

## Build `Dockerfile`

```shell
docker build \
  --build-arg PASSWORD=docker \
  --build-arg SSH_PUB_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  --build-arg SSH_PRIV_KEY="$(cat ~/.ssh/id_rsa)" \
  --build-arg AUTH_KEY="$(cat ~/.ssh/authorized_keys)" \
  --build-arg USE_LOCAL_SSH_KEY="${USE_LOCAL_SSH_KEY}" \
  -t tvm ./

docker run -p 20334:22 -itd --name tvm tvm
```

## How to Convert TFLite Model into C++

### Copy `tflite` Files to the Docker Container

```shell
docker cp <TFLITE_FILE_PATH> tvm:/home/docker/
```

## References

* [딥러닝 모델 처리 가속을 위한 딥러닝 컴파일러 개발 현황 및 기술 소개](https://mediasvr.egentouch.com/egentouch.media/apiFile.do?action=view&SCHOOL_ID=1007002&URL_KEY=fe245c47-4890-4c18-be51-b60b2d010de0)
* [TVM: An Automated End-to-End Optimizing Compiler for Deep Learning](https://homes.cs.washington.edu/~arvind/papers/tvm.pdf)

# tflite2cpp

Research and implementation notes on porting TensorFlow Lite models to C++ for efficient inference

---

## AOT Conversion from TFLite using TVM

This project demonstrates converting a TFLite model into standalone C code using TVM's Ahead-Of-Time (AOT) executor. The result is a `.tar` archive containing source files that can be compiled without linking any specialized TVM runtime libraries, fulfilling the goal of **no runtime dependencies**.

### Types of IR in TVM

| Level             | IR Name                  | Description                                                                                                                                   |
|------------------|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| High-level        | Relay                    | A functional programming-based IR representing neural networks; used for optimizations like operator fusion, layout transforms, etc.          |
| Mid-level         | Tensor Expression (TE)   | Describes how a computation should be computed using loops and indexing (algorithm + schedule). It is lower-level than Relay.              |
| Low-level         | TIR (Tensor IR)          | TVM’s imperative IR represents lowered loops, memory accesses, and hardware-level parallelism (e.g., threads).                           |
| Hardware-specific | CodeGen IRs              | These representations target CUDA, Metal, LLVM IR, etc. They are used during code generation for specific backends.          

### Traditional Runtime vs AOT

| Feature                      | Traditional Runtime (Graph / VM)     | AOT (Static / CRT)                       |
|-----------------------------|--------------------------------------|-------------------------------------------|
| **Compilation Style**       | Partially compiled, JIT or interpreted | Fully compiled at build-time (AOT)       |
| **Runtime Dependency**      | Requires full-featured TVM runtime   | Minimal CRT (C Runtime), no JIT support   |
| **Dynamic Shape Support**   | Yes                                  | Limited or none (static only)             |
| **Execution Flexibility**   | High (can adapt to input variation)  | Low (fixed graph & input/output shapes)   |
| **Memory Allocation**       | Dynamic                              | Static (pre-planned at compile time)      |
| **Runtime Code Size**       | Larger (due to interpreter, graph, etc.) | Very small (bare-metal friendly)       |
| **Deployment Target**       | Linux, Android, servers              | Embedded devices, MCU, RTOS               |
| **Startup Time**            | Slower (initialization + parsing)    | Faster (no runtime graph load)            |
| **Ease of Debugging**       | Easier with full TVM runtime         | Harder (low-level, limited tooling)       |
| **Main Use Cases**          | Research, dynamic model scenarios    | Deployment to resource-constrained devices|

### Objective

- Convert a TFLite model into pure C code (i.e., no dynamic libraries or TVM runtime).
- Ensure `expf(...)` calls are used instead of `tir.exp(...)` to avoid unresolved intrinsics during code generation.
- Keep the code hardware-agnostic to facilitate cross-compilation with custom flags later.

#### **Key Options and Parameters**:

- **`"c -libs=math"`**: We specify `-libs=math` so that the final code can use `expf()` from the standard math library (`-lm`).
- **AOT Executor**: TVM's AOT executor generates minimal C sources with no additional runtime requirements.  
- **`opt_level=0`** with disabled advanced passes: By disabling vectorization, storage rewriting, auto-scheduler, and meta-schedule, we prevent transformations that might re-insert `tir.exp` or complicate the final code.  
- **`replace_exp_pass`**: This custom TIR pass scans the final IR to replace any occurrences of `tir.exp(...)` with `call_pure_extern("float32", "expf", ...)`. This ensures that the final code compiles cleanly without unresolved references.

### **Workflow**:

-  **Load TFLite**: TVM's `from_tflite` function loads the TFLite model into memory and parses it.  
-  **Relay Module**: We create a Relay IR module from the TFLite model, capturing the input shapes and data types.  
-  **Build**: We invoke `relay.build()` with a minimal set of passes (`opt_level=0`) and the AOT executor. As part of the build, the system calls our `replace_exp_pass` in the final lowering stage.  
-  **Export**: The final library is exported to `model.tar` (an archive with `.c`, `.h`, and metadata).  
-  **Compile**: End users can untar the result and compile it with standard or cross toolchains, linking `-lm` if needed.

### Building the Generated Sources

1. Run `python convert_tflite.py` with the following arguments:

```bash
python convert_tflite.py <model.tflite> <input_name> "[1,224,224,3]" float32 ./output
```  
This outputs `./output/model.tar`.  

2. Unpack `model.tar`:  

```bash
cd output
tar -xf model.tar
```
  
3. In the extracted folder, clone dlpack (build dependency): 

```bash
git clone https://github.com/dmlc/dlpack.git
```

4. Compile the `c` files with your desired compiler flags: 

```bash
gcc -c *.c  -I/opt/tvm/include -I./dlpack/include -lm
```

5. Use object files where you need to use inferencing:

```bash
gcc main.c output/*.o -lm
```

---

## References

* [딥러닝 모델 처리 가속을 위한 딥러닝 컴파일러 개발 현황 및 기술 소개](https://mediasvr.egentouch.com/egentouch.media/apiFile.do?action=view&SCHOOL_ID=1007002&URL_KEY=fe245c47-4890-4c18-be51-b60b2d010de0)
* [TVM: An Automated End-to-End Optimizing Compiler for Deep Learning](https://homes.cs.washington.edu/~arvind/papers/tvm.pdf)

---

## Appendix

### A. Build `Dockerfile`

```bash
docker build \
  --build-arg PASSWORD=docker \
  --build-arg SSH_PUB_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  --build-arg SSH_PRIV_KEY="$(cat ~/.ssh/id_rsa)" \
  --build-arg AUTH_KEY="$(cat ~/.ssh/authorized_keys)" \
  --build-arg USE_LOCAL_SSH_KEY="${USE_LOCAL_SSH_KEY}" \
  -t tvm ./

docker run -p 20334:22 -itd --name tvm tvm
```

### B. Copy `tflite` Files to the Docker Container

```bash
docker cp <TFLITE_FILE_PATH> tvm:/home/docker/
```

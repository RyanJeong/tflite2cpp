import os
import sys
import ast

import tvm
from tvm import relay
from tvm.relay.frontend import from_tflite
from tflite.Model import Model

# (A) Define a custom TIR pass to replace tir.exp(...) with expf(...)
# -------------------------------------------------------------------
from tvm.tir.stmt_functor import ir_transform
from tvm.tir.transform import prim_func_pass


@prim_func_pass(opt_level=0)
def replace_exp_pass(func, mod, ctx):
    """
    This pass looks for tir.exp(...) calls in a TIR PrimFunc,
    and replaces them with an extern call to expf(...).
    """
    def previsit(node):
        if isinstance(node, tvm.tir.Call) and node.op.name == "tir.exp":
            return tvm.tir.call_pure_extern("float32", "expf", [node.args[0]])
        return None

    new_body = ir_transform(func.body, previsit, None)
    return func.with_body(new_body)


def main():
    if len(sys.argv) != 6:
        print(
            "Usage: python convert_tflite.py [TFLITE_MODEL] [INPUT_NAME] "
            "[INPUT_SHAPE] [INPUT_DTYPE] [OUTPUT_DIR]"
        )
        sys.exit(1)

    # Parse command-line arguments
    model_path = sys.argv[1]
    input_name = sys.argv[2]
    input_shape = ast.literal_eval(sys.argv[3])
    input_dtype = sys.argv[4]
    output_dir = sys.argv[5]

    # 1) Load TFLite model from file
    with open(model_path, "rb") as f:
        tflite_model_buf = f.read()
    tflite_model = Model.GetRootAsModel(tflite_model_buf, 0)

    # 2) Convert the TFLite model into a Relay module
    shape_dict = {input_name: input_shape}
    dtype_dict = {input_name: input_dtype}
    relay_mod, params = from_tflite(tflite_model, shape_dict, dtype_dict)

    # 3) Specify target and runtime settings
    #    - "c -libs=math": needed for expf(...) in math library
    target = tvm.target.Target("c -libs=math")
    runtime = tvm.relay.build_module.Runtime("crt")   # C runtime
    executor = tvm.relay.build_module.Executor("aot") # AOT executor

    # 4) PassContext to disable most optimizations
    #    - Also insert our custom pass at the final lowering stage
    with tvm.transform.PassContext(
        opt_level=0,
        config={
            "relay.backend.use_auto_scheduler": False,
            "relay.backend.use_meta_schedule": False,
            "tir.disable_vectorize": True,
            "tir.disable_storage_rewrite": True,
            "tir.add_lower_pass": [(99, replace_exp_pass)],
        }
    ):
        # 5) Build the Relay module (Relay -> TIR -> final C code)
        lowered = relay.build(
            relay_mod,
            target=target,
            params=params,
            runtime=runtime,
            executor=executor,
        )

    # 6) Export the AOT library to a .tar file inside the provided OUTPUT_DIR
    os.makedirs(output_dir, exist_ok=True)
    model_tar_path = os.path.join(output_dir, "model.tar")
    lowered.export_library(model_tar_path)

    print(f"[OK] Exported AOT model to {model_tar_path}")


if __name__ == "__main__":
    main()


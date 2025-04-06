#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

// Minimal TVM type definition
typedef union {
    void* v_handle;
    int64_t v_int64;
    double v_float64;
    void* v_pointer;
} TVMValue;

// Define a constant for the type code for float32.
// In TVM runtime, type codes are defined in the runtime header.
// Here, we assume that for float32 the type code is 2.
#define kTVMFloat 2

// Declare the generated function. This prototype must match the one in your generated library.
#ifdef __cplusplus
extern "C" {
#endif
int32_t tvmgen_default_run(TVMValue* args, int* type_code, int num_args,
                           TVMValue* out_value, int* out_type_code, void* resource_handle);
#ifdef __cplusplus
}
#endif

/*
 * Usage: ./run_model <input_file> <num_elements>
 *
 * - <input_file> should be a text file containing floating point numbers
 *   (whitespace separated) for the input tensor.
 *   e.g., for a 1x224x224x3 input, 150528 floats data will be included
 * - <num_elements> is the total number of float values expected for the input.
 *   e.g., for a 1x224x224x3 input, 150528
 *
 * This main function:
 *   - Reads input data from the file,
 *   - Allocates buffers for input and output,
 *   - Calls the generated model function,
 *   - And prints the first 10 output values.
 */
int main(int argc, char* argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input_file> <num_elements>\n", argv[0]);
        return 1;
    }

    // Parse the number of elements from command-line argument.
    int num_elements = atoi(argv[2]);
    if (num_elements <= 0) {
        fprintf(stderr, "Error: num_elements must be positive.\n");
        return 1;
    }

    // Allocate memory for input and output buffers.
    // NOTE: Adjust the output buffer size as needed for your model.
    float *input_data = (float *)malloc(num_elements * sizeof(float));
    float *output_data = (float *)malloc(num_elements * sizeof(float));
    if (input_data == NULL || output_data == NULL) {
        fprintf(stderr, "Memory allocation failed.\n");
        free(input_data);
        free(output_data);
        return 1;
    }

    // Read the input data from file.
    FILE *fp = fopen(argv[1], "r");
    if (fp == NULL) {
        fprintf(stderr, "Failed to open input file %s.\n", argv[1]);
        free(input_data);
        free(output_data);
        return 1;
    }
    for (int i = 0; i < num_elements; i++) {
        if (fscanf(fp, "%f", &input_data[i]) != 1) {
            fprintf(stderr, "Error reading input data at element %d.\n", i);
            fclose(fp);
            free(input_data);
            free(output_data);
            return 1;
        }
    }
    fclose(fp);

    // Prepare TVMValue arrays for inputs and outputs.
    // Here, we assume the model has exactly one input and one output.
    TVMValue args[1];
    int input_type_codes[1];
    args[0].v_pointer = (void*)input_data;
    input_type_codes[0] = kTVMFloat;

    TVMValue outs[1];
    int output_type_codes[1];
    outs[0].v_pointer = (void*)output_data;
    output_type_codes[0] = kTVMFloat;

    // Call the generated model function.
    // resource_handle can be set to NULL if not used.
    int32_t ret = tvmgen_default_run(args, input_type_codes, 1, outs, output_type_codes, NULL);
    if (ret != 0) {
        fprintf(stderr, "Model execution failed with error code: %d\n", ret);
        free(input_data);
        free(output_data);
        return 1;
    }

    // Print the first 10 output values for verification.
    printf("Model output (first 10 values):\n");
    for (int i = 0; i < 10 && i < num_elements; i++) {
        printf("%f ", output_data[i]);
    }
    printf("\n");

    // Clean up.
    free(input_data);
    free(output_data);

    return 0;
}

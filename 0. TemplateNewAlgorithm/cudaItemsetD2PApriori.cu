#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <bits/stdc++.h>
#include <cuda_runtime.h>
#include <unordered_map>
#include <iostream>
#include <string.h>
#include <time.h>

#define MAX_NODES 6000  // Maximum nodes in the FP-Tree
#define EMPTY -1

typedef struct {
    int id; 
    int processed; // 1 signifies it was processed
    int itemSet;
    int count; 
    int parent;
    int nextSibling; 
    int firstChild; 
} Node; 

// Calculates the distance between two instances
__device__ float generateItemSet(float* instance_A, float* instance_B, int num_attributes) {
    float sum = 0;
    
    for (int i = 0; i < num_attributes-1; i++) {
        float diff = instance_A[i] - instance_B[i];
        //printf("instance a and b were %.3f %.3f\n", instance_A[i] ,instance_B[i]);
        sum += diff*diff;
    }
    //printf("sum was %.3f\n,", sum);
    return sqrt(sum);
}

__global__ void processItemSets(char *inData, int minimumSetNum, int *d_Offsets, int totalRecords, int blocksPerGrid) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;

    // Shared memory is treated as a single contiguous block
    extern __shared__ int sharedMemory[];

    char* line = inData + d_Offsets[tid];
    bool inNumber = false;
    int itemCount = 0;
    int number = 0;
    int items[32];
    // Initialize the shared memory (done by thread 0 in each block)
    if (tid <= 9) {
        printf("are are in tid %d\n", tid);
        //Extract items from the input line
        for (char* current = line; *current != '\n' && *current != '\0'; current++) {
            if (*current >= '0' && *current <= '9') {
                number = number * 10 + (*current - '0');
                inNumber = true;
            } else if (inNumber) {
                
                items[itemCount] = number;
                itemCount++;
                number = 0; 
                inNumber = false;
                
            }
           
        }

        if (inNumber) {
             items[itemCount++] = number;
        }
        for(int i = 0; i < itemCount; i++){
            printf("%d", items[i]);
            
        }
        
        
    }
    __syncthreads();

    // Parse the input and build the FP-Tree
    if (tid < totalRecords) {
        
    }


    
}

// Implements a threaded kNN where for each candidate query an in-place priority queue is maintained to identify the nearest neighbors
int KNN() {   
    clock_t cpu_start_withSetup = clock();
    
    clock_t setupTimeStart = clock();
    //int lineCountInDataset = 1692081;
    int lineCountInDataset = 55012;
    const char* inDataFilePath = "../sortedDataBase.txt";

    FILE* file = fopen(inDataFilePath, "r");

    // Get the file size
    fseek(file, 0, SEEK_END);
    size_t file_size = ftell(file);
    rewind(file);

    char* h_buffer = (char*)malloc(file_size);
    fread(h_buffer, 1, file_size, file);
    

    // Count the number of lines and create offsets
    int* h_offsets = (int*)malloc((file_size + 1) * sizeof(int));
    int lineCount = 0;
    h_offsets[lineCount++] = 0; // First line starts at the beginning
    
    for (size_t i = 0; i < file_size; i++) {
        //printf("are we in size?");
        if (h_buffer[i] == '\n') {
            //printf("we are in the newline stuff");
            h_offsets[lineCount++] = i + 1; // Next line starts after '\n'
            
        }
    }
    
    // Allocate memory to hold the file contents
    char* h_text = (char*)malloc(file_size);

    // Read the file into the host buffer
    fread(h_text, 1, file_size, file);
    //fclose(file);
    //size_t sharedMemSize = (6 * MAX_NODES) * sizeof(int) +  1 * sizeof(int) ;  // 5 arrays + nodeCounter
    
    // Allocate memory on the GPU
    char* d_text;
    int* d_offsets; 
    cudaMalloc(&d_text, file_size);
    cudaMalloc(&d_offsets, lineCountInDataset * sizeof(int));

    // Copy the file contents to the GPU
    cudaMemcpy(d_text, h_buffer, file_size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_offsets, h_offsets, lineCountInDataset * sizeof(int), cudaMemcpyHostToDevice);
    int threadsPerBlock = 32;
    int blocksPerGrid = ((lineCountInDataset + threadsPerBlock) - 1) /  threadsPerBlock; //how do we know how many blocks we need to use?
    //printf("BlocksPerGrid = %d\n", blocksPerGrid);
    printf("number of threads is roughly %d\n", threadsPerBlock*blocksPerGrid);


    

    int minItemCount = 3; //setting the minimum # of items to be considered an itemset

    //here I would want to generate all itemsets

    clock_t setupTimeEnd = clock();

    cudaEvent_t startEvent, stopEvent;
    cudaEventCreate(&startEvent);
    cudaEventCreate(&stopEvent);
    float cudaElapsedTime;

    
    cudaEventRecord(startEvent);
    processItemSets<<<blocksPerGrid, threadsPerBlock>>>(d_text, minItemCount, d_offsets, lineCountInDataset, blocksPerGrid);
    cudaDeviceSynchronize();
    cudaEventRecord(stopEvent);
    cudaEventSynchronize(stopEvent);

    // Print the elapsed time (milliseconds)
    cudaEventElapsedTime(&cudaElapsedTime, startEvent, stopEvent);
    printf("CUDA Kernel Execution Time: %.3f ms\n", cudaElapsedTime);

    // ensure there are no kernel errors
    cudaError_t cudaError = cudaGetLastError();
    if(cudaError != cudaSuccess) {
        fprintf(stderr, "processItemSets cudaGetLastError() returned %d: %s\n", cudaError, cudaGetErrorString(cudaError));
        exit(EXIT_FAILURE);
    }

    clock_t retrieveGPUResultsStart = clock();
    clock_t retrieveGPUResultsEnd = clock();

    // global reduction will be written to file
    FILE *resultsFile = fopen("cudaItemSetMiningResults.txt", "w");
    if (resultsFile == NULL) {
        perror("Error opening results file");
        return 1;
    }
    

    // Record end time
    clock_t cpu_end_withSetup = clock();
    // Calculate elapsed time in milliseconds
    // float cpuElapsedTime = ((float)(cpu_end - cpu_start)) / CLOCKS_PER_SEC * 1000.0;
    // float cpuElapsedTimeSetup = ((float)(cpu_end_withSetup - cpu_start_withSetup)) / CLOCKS_PER_SEC * 1000.0;
    // float setupTime = ((float)(setupTimeEnd - setupTimeStart)) / CLOCKS_PER_SEC * 1000.0;
    // float gpuRetrievalTime = ((float)(retrieveGPUResultsEnd - retrieveGPUResultsStart)) / CLOCKS_PER_SEC * 1000.0;

    // printf("CPU Execution Time: %.3f ms\n", cpuElapsedTime);
    // printf("Total Runtime: %.3f ms\n", cudaElapsedTime + cpuElapsedTime);
    // printf("Total Runtime (with setup/file write): %.3f ms\n", cpuElapsedTimeSetup);
    // printf("Total Setup Time: %.3f ms\n", setupTime);
    // printf("Total GPU Results Retrieval Time: %.3f ms\n", gpuRetrievalTime);
    //printf("Proccessed %d nodes\n", totalNodes);
    // // Print the aggregated counts (if has no child then follow up to the parent)
    // printf("{ ");
    // for (const auto& [itemSet, count] : map) {
    //     std::cout << itemSet << ": " << count << '\n';
    // } printf("}");
    return 1;
}

int main(int argc, char *argv[])
{
    

    int x = KNN();
    return -1;  
}
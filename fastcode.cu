#include <cuda.h>
#include <cuda_runtime.h>
#include <opencv2/core/core.hpp>
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/imgproc/imgproc.hpp"
#include "opencv2/core/cuda_devptrs.hpp"
#include "opencv2/core/cuda_types.hpp"
#include "opencv2/cvconfig.h"
#include "opencv2/cudaarithm.hpp"
#include "fastcode.h"

using namespace cv;
using namespace cv::cuda;
using namespace std;

// reference: http://stackoverflow.com/questions/24613637/custom-kernel-gpumat-with-float

namespace fastcode{
    // cuda implementation of maskShow
    __global__ void maskShowKernel(const PtrStepSz<uchar> mask, PtrStepSz<uchar> mask4show){
        int x = blockIdx.x * blockDim.x + threadIdx.x;
        int y = blockIdx.y * blockDim.y + threadIdx.y;
        if(x < mask.rows && y < mask.cols){
            switch(mask(x,y)){
                case GC_BGD:
                    mask4show(x,y) = 0;
                    break;
                case GC_PR_BGD:
                    mask4show(x,y) = 1;
                    break;
                case GC_PR_FGD:
                    mask4show(x,y) = 2;
                    break;
                case GC_FGD:
                    mask4show(x,y) = 3;
            }
        }
    }

    void maskShowCaller(const Mat & mask, Mat & mask4show){
        GpuMat gmask;
        gmask.upload(mask);
        mask4show.create(mask.size(), CV_8UC1);
        GpuMat gmask4show;
        gmask4show.upload(mask4show);

        dim3 DimBlock(16,16);
        dim3 DimGrid(static_cast<int>(std::ceil(mask.size().height /
                        static_cast<double>(DimBlock.x))), 
                        static_cast<int>(std::ceil(mask.size().width / 
                        static_cast<double>(DimBlock.y))));
        maskShowKernel<<<DimGrid, DimBlock>>>(gmask, gmask4show);
        gmask4show.download(mask4show);
    }

    // cuda implementation of segResultShow
    __global__ void segResultShowKernel(const PtrStepSz<uchar> mask, PtrStepSz<uchar> segResult){
        int x = blockIdx.x * blockDim.x + threadIdx.x;
        int y = blockIdx.y * blockDim.y + threadIdx.y;
        if(x < mask.rows && y < mask.cols){
            if(mask(x,y) == GC_BGD || mask(x,y) == GC_PR_BGD){
                 segResult(x,y) = segResult(x,y) / 4;
            }
        }
    }

    void segResultShowCaller(const Mat & img, const Mat & mask, Mat & segResult){
        GpuMat gmask;
        gmask.upload(mask);
        img.copyTo(segResult);
        GpuMat gsegResult;
        gsegResult.upload(segResult);

        dim3 DimBlock(32,32);
        dim3 DimGrid(static_cast<int>(std::ceil(mask.size().height /
                        static_cast<double>(DimBlock.x))), 
                        static_cast<int>(std::ceil(mask.size().width / 
                        static_cast<double>(DimBlock.y))));
        segResultShowKernel<<<DimGrid, DimBlock>>>(gmask, gsegResult);
        gsegResult.download(segResult);
    }
    // cuda implementation of maskBinary
    __global__ void maskBinaryKernel(const PtrStepSz<uchar> mask, PtrStepSz<uchar> maskResult){
        int x = blockIdx.x * blockDim.x + threadIdx.x;
        int y = blockIdx.y * blockDim.y + threadIdx.y;
        if(x < mask.rows && y < mask.cols){
            if(mask(x,y) == GC_FGD || mask(x,y) == GC_PR_FGD){
                 maskResult(x,y) = 255;
            }else{
                 maskResult(x,y) = 0;
            }
        }
    }

    void maskBinaryCaller(const Mat & mask, Mat & maskResult){
        GpuMat gmask;
        gmask.upload(mask);
        maskResult.create(mask.size(), CV_8UC1);
        GpuMat gmaskResult;
        gmaskResult.upload(maskResult);

        dim3 DimBlock(32,32);
        dim3 DimGrid(static_cast<int>(std::ceil(mask.size().height /
                        static_cast<double>(DimBlock.x))), 
                        static_cast<int>(std::ceil(mask.size().width / 
                        static_cast<double>(DimBlock.y))));
        maskBinaryKernel<<<DimGrid, DimBlock>>>(gmask, gmaskResult);
        gmaskResult.download(maskResult);
    }
    // cuda implementation of threshold BG/FG determine
    __global__ void thresholdKernel(const PtrStepSz<uchar> img1, const PtrStepSz<uchar> img2, const PtrStepSz<uchar> img3, PtrStepSz<uchar> maskFG, PtrStepSz<uchar> maskBG){
        int x = blockIdx.x * blockDim.x + threadIdx.x;
        int y = blockIdx.y * blockDim.y + threadIdx.y;
        if(x < mask.rows && y < mask.cols){
            if(img1(x,y)>30||img2(x,y)>30||img3(x,y)>30) maskFG(x,y) = 1;
            if(img1(x,y)<10&&img2(x,y)<10&&img3(x,y)<10) maskBG(x,y) = 1;
        }
    }

    void thresholdCaller(const Mat & img1, const Mat & img2, const Mat & img3, Mat & maskFG, Mat & maskBG){
        GpuMat gimg1, gimg2, gimg3, gmaskFG, gmaskBG;
        gimg1.upload(img1);
        gimg2.upload(img2);
        gimg3.upload(img3);
        gmaskFG.upload(maskFG);
        gmaskBG.upload(maskBG);

        dim3 DimBlock(32,32);
        dim3 DimGrid(static_cast<int>(std::ceil(img1.size().height /
                        static_cast<double>(DimBlock.x))), 
                        static_cast<int>(std::ceil(img1.size().width / 
                        static_cast<double>(DimBlock.y))));
        thresholdKernel<<<DimGrid, DimBlock>>>(gimg1, gimg2, gimg3, gmaskFG, gmaskBG);
        gmaskFG.download(maskFG);
        gmaskBG.download(maskBG);
    }
}

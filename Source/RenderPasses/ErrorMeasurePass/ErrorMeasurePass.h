/***************************************************************************
 # Copyright (c) 2020, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#pragma once
#include "Falcor.h"
#include "Utils/Algorithm/ComputeParallelReduction.h"

using namespace Falcor;

class ErrorMeasurePass : public RenderPass
{
public:
    using SharedPtr = std::shared_ptr<ErrorMeasurePass>;

    static SharedPtr create(RenderContext* pRenderContext = nullptr, const Dictionary& dict = {});

    virtual std::string getDesc() override { return "Measures error with respect to a reference image"; }
    virtual Dictionary getScriptingDictionary() override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override;
    virtual void updateDict(const Dictionary& dict) override;

private:
    ErrorMeasurePass(const Dictionary& dict);

    bool init(RenderContext* pRenderContext, const Dictionary& dict);

    void SaveOutputToFile();
    void loadReference();
    Texture::SharedPtr getReference(const RenderData& renderData) const;
    void openMeasurementsFile();
    void saveMeasurementsToFile();

    void runDifferencePass(RenderContext* pRenderContext, const RenderData& renderData);
    void runReductionPasses(RenderContext* pRenderContext, const RenderData& renderData);

    ComputePass::SharedPtr mpErrorMeasurerPass;
    ComputeParallelReduction::SharedPtr mpParallelReduction;

    struct
    {
        float3 error;           ///< Error (either L1 or MSE) in RGB.
        float  avgError;        ///< Error averaged over color components.
        bool   valid = false;
    } mMeasurements;

    // Internal state
    float3                  mRunningError = float3(0.f, 0.f, 0.f);
    float                   mRunningAvgError = -1.f;        ///< A negative value indicates that both running error values are invalid.

    Texture::SharedPtr      mpReferenceTexture;
    Texture::SharedPtr      mpDifferenceTexture;

    Buffer::SharedPtr       mpResultBuffer;
    int                     mFrameCount = 0;
    CpuTimer::TimePoint				mStartTimePoint;
    CpuTimer::TimePoint				mPrevTimePoint;
    CpuTimer                mTimer;
    std::vector<double> mTimeStamps;

    std::ofstream           mMeasurementsFile;

    // UI variables
    std::string             mReferenceImagePath;                ///< Path to the reference used in the comparison.
    std::string             mMeasurementsFilePath;              ///< Path to the output file where measurements are stored (.csv).

    bool                    mIgnoreBackground = true;           ///< If true, do not measure error on pixels that belong to the background.
    bool                    mComputeSquaredDifference = true;   ///< Compute the square difference when creating the difference image.
    bool                    mComputeAverage = false;            ///< Compute the average of the RGB components when creating the difference image.
    bool                    mUseLoadedReference = false;        ///< If true, use loaded reference image instead of input.
    bool                    mReportRunningError = true;         ///< Use exponetial moving average (EMA) for the computed error.
    float                   mRunningErrorSigma = 0.995f;        ///< Coefficient used for the exponential moving average. Larger values mean slower response.

    bool                    mRequestSaveToFile = false;

    enum class OutputId
    {
        Source,
        Reference,
        Difference,
        Count
    };

    OutputId                mSelectedOutputId = OutputId::Source;

    static const Gui::RadioButtonGroup sOutputSelectionButtons;
    static const Gui::RadioButtonGroup sOutputSelectionButtonsSourceOnly;

    template <typename T>
    void readbackBufferData(Falcor::Buffer::SharedPtr buf, T* var, uint32_t numElems)
    {
        if (numElems > 0)
        {
            const T* bufPtr = reinterpret_cast<const T*>(buf->map(Buffer::MapType::Read));
            CopyMemory(var, bufPtr, sizeof(T) * numElems);
            buf->unmap();
        }
    }

};

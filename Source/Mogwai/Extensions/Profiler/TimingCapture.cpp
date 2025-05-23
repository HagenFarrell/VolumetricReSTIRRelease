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
#include "stdafx.h"
#include "TimingCapture.h"

namespace Mogwai
{
    namespace
    {
        const std::string kScriptVar = "tc";
        const std::string kCaptureFrameTime = "captureFrameTime";
        const std::string kCapturePassTime = "capturePassTime";
    }

    MOGWAI_EXTENSION(TimingCapture);

    TimingCapture::UniquePtr TimingCapture::create(Renderer* pRenderer)
    {
        return UniquePtr(new TimingCapture(pRenderer));
    }

    void TimingCapture::scriptBindings(Bindings& bindings)
    {
        auto& m = bindings.getModule();

        pybind11::class_<TimingCapture> timingCapture(m, "TimingCapture");

        bindings.addGlobalObject(kScriptVar, this, "Timing Capture Helpers");

        // Members
        timingCapture.def(kCaptureFrameTime.c_str(), &TimingCapture::captureFrameTime, "filename"_a);
        timingCapture.def(kCapturePassTime.c_str(), &TimingCapture::capturePassTime, "filename"_a, "passname"_a);
    }

    void TimingCapture::beginFrame(RenderContext* pRenderContext, const Fbo::SharedPtr& pTargetFbo)
    {
        recordPreviousFrameTime();
        recordPreviousPassTimes();
    }

    void TimingCapture::captureFrameTime(std::string filename)
    {
        if (mFrameTimeFile.is_open())
            mFrameTimeFile.close();

        if (!filename.empty())
        {
            if (doesFileExist(filename))
            {
                logWarning("Frame times in file '" + filename + "' will be overwritten.");
            }

            mFrameTimeFile.open(filename, std::ofstream::trunc);
            if (!mFrameTimeFile.is_open())
            {
                logError("Failed to open file '" + filename + "' for writing. Ignoring call.");
            }
        }
    }

    void TimingCapture::capturePassTime(std::string filename, std::string passName)
    {
        gProfileEnabled = true;
        int passIndex = -1;
        for (int i = 0; i < mPassNames.size(); i++)
            if (mPassNames[i] == passName)
            {
                passIndex = i;
                break;
            }

        if (passIndex >= 0 && mPassTimeFiles[passIndex].is_open())
            mPassTimeFiles[passIndex].close();

        if (!filename.empty())
        {
            if (doesFileExist(filename))
            {
                logWarning("Frame times in file '" + filename + "' will be overwritten.");
            }


            if (passIndex == -1) // create new ofstream
            {
                mPassTimeFiles.push_back(std::ofstream());
                mPassNames.push_back(passName);
                mPassTimeFiles.back().open(filename, std::ofstream::trunc);
                passIndex = (int)mPassTimeFiles.size() - 1;
            }
            else
            {
                mPassTimeFiles[passIndex].open(filename, std::ofstream::trunc);
            }

            if (!mPassTimeFiles[passIndex].is_open())
            {
                logError("Failed to open file '" + filename + "' for writing. Ignoring call.");
            }
        }
    }

    void TimingCapture::recordPreviousFrameTime()
    {
        if (!mFrameTimeFile.is_open()) return;

        // The FrameRate object is updated at the start of each frame, the first valid time is available on the second frame.
        auto& frameRate = gpFramework->getFrameRate();
        if (frameRate.getFrameCount() > 1)
            mFrameTimeFile << frameRate.getLastFrameTime() << std::endl;
    }


    void TimingCapture::recordPreviousPassTimes()
    {
        auto& frameRate = gpFramework->getFrameRate();

        if (frameRate.getFrameCount() > 1)
        {
            for (int i = 0; i < mPassNames.size(); i++)
            {
                std::string passName = mPassNames[i];
                double passTime = Profiler::getEventGpuTime(passName) / 1000.0;
                mPassTimeFiles[i] << passTime << std::endl;
            }
        }
    }


}

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
#include "Core/Program/Program.h"
#include "Core/API/RootSignature.h"
#include "../RtStateObject.h"
#include "../ShaderTable.h"
#include "Scene/Scene.h"

namespace Falcor
{
    /** Ray tracing program. See GraphicsProgram and ComputeProgram to manage other types of programs.
    */
    class dlldecl RtProgram : public Program
    {
    public:
        using SharedPtr = std::shared_ptr<RtProgram>;
        using SharedConstPtr = std::shared_ptr<const RtProgram>;

        using DefineList = Program::DefineList;

        struct dlldecl DescExtra
        {
        public:
            struct GroupInfo
            {
                int32_t groupIndex = -1;
            };

            /** Set the max recursion depth
            */
            void setMaxTraceRecursionDepth(uint32_t maxDepth) { mMaxTraceRecursionDepth = maxDepth; }

            std::vector<GroupInfo> mRayGenEntryPoints;
            std::vector<GroupInfo> mMissEntryPoints;
            std::vector<GroupInfo> mHitGroups;
            std::vector<GroupInfo> mParticleHitGroups;
            std::vector<GroupInfo> mCurveHitGroups;
            uint32_t mMaxTraceRecursionDepth = 1;
        };

        class dlldecl Desc : public DescExtra
        {
        public:
            Desc() { init(); }
            Desc(const std::string& filename) : mBaseDesc(filename) { init(); }

            Desc& addShaderLibrary(const std::string& filename);
            Desc& setRayGen(const std::string& raygen);
            Desc& addRayGen(const std::string& raygen);
            Desc& addMiss(uint32_t missIndex, const std::string& miss);
            Desc& addHitGroup(uint32_t hitIndex, const std::string& closestHit, const std::string& anyHit = "", const std::string& intersection = "");
            Desc& addParticleHitGroupFromHitGroup(uint32_t hitIndex);
            Desc& addParticleHitGroup(uint32_t hitIndex, const std::string& closestHit, const std::string& anyHit = "", const std::string& intersection = "");
            Desc& addCurveHitGroupFromHitGroup(uint32_t hitIndex);
            Desc& addCurveHitGroup(uint32_t hitIndex, const std::string& closestHit, const std::string& anyHit = "", const std::string& intersection = "");
            Desc& addDefine(const std::string& define, const std::string& value);
            Desc& addDefines(const DefineList& defines);

            /** Set the compiler flags. Replaces any previously set flags.
            */
            Desc& setCompilerFlags(Shader::CompilerFlags flags) { mBaseDesc.setCompilerFlags(flags); return *this; }

        private:
            friend class RtProgram;

            void init();

            Program::Desc mBaseDesc;
            DefineList mDefineList;
        };

        /** Create a new ray tracing program.
            \param[in] desc The program description.
            \param[in] maxPayloadSize The maximum ray payload size in bytes.
            \param[in] maxAttributesSize The maximum attributes size in bytes.
            \return A new object, or an exception is thrown if creation failed.
        */
        static RtProgram::SharedPtr create(const Desc& desc, uint32_t maxPayloadSize = FALCOR_RT_MAX_PAYLOAD_SIZE_IN_BYTES, uint32_t maxAttributesSize = D3D12_RAYTRACING_MAX_ATTRIBUTE_SIZE_IN_BYTES);

        /** Get the max recursion depth
        */
        uint32_t getMaxTraceRecursionDepth() const { return mDescExtra.mMaxTraceRecursionDepth; }

        /** Get the raytracing state object for this program
        */
        RtStateObject::SharedPtr getRtso(RtProgramVars* pVars);

        // Ray-gen
        uint32_t getRayGenProgramCount() const { return (uint32_t) mDescExtra.mRayGenEntryPoints.size(); }
        uint32_t getRayGenIndex(uint32_t index) const { return mDescExtra.mRayGenEntryPoints[index].groupIndex; }

        // Hit
        uint32_t getHitProgramCount() const { return (uint32_t) mDescExtra.mHitGroups.size(); }
        uint32_t getHitIndex(uint32_t index) const { return mDescExtra.mHitGroups[index].groupIndex; }

        // Curve Hit
        uint32_t getCurveHitProgramCount() const { return (uint32_t)mDescExtra.mCurveHitGroups.size(); }
        uint32_t getCurveHitIndex(uint32_t index) const { return mDescExtra.mCurveHitGroups[index].groupIndex; }

        // particle hit
        uint32_t getParticleHitProgramCount() const { return (uint32_t)mDescExtra.mParticleHitGroups.size(); }
        uint32_t getParticleHitIndex(uint32_t index) const { return mDescExtra.mParticleHitGroups[index].groupIndex; }

        // Miss
        uint32_t getMissProgramCount() const { return (uint32_t) mDescExtra.mMissEntryPoints.size(); }
        uint32_t getMissIndex(uint32_t index) const { return mDescExtra.mMissEntryPoints[index].groupIndex; }

        /** Set the scene
        */
        void setScene(const Scene::SharedPtr& pScene);

        DescExtra const& getDescExtra() const { return mDescExtra; }

    protected:
        void init(const Desc& desc);

        EntryPointGroupKernels::SharedPtr createEntryPointGroupKernels(
            const std::vector<Shader::SharedPtr>& shaders,
            EntryPointGroupReflection::SharedPtr const& pReflector) const override;

    private:
        RtProgram(RtProgram const&) = delete;
        RtProgram& operator=(RtProgram const&) = delete;

        RtProgram(const Desc& desc, uint32_t maxPayloadSize = FALCOR_RT_MAX_PAYLOAD_SIZE_IN_BYTES, uint32_t maxAttributesSize = D3D12_RAYTRACING_MAX_ATTRIBUTE_SIZE_IN_BYTES);

        DescExtra mDescExtra;

        uint32_t mMaxPayloadSize;
        uint32_t mMaxAttributesSize;

        using StateGraph = Falcor::StateGraph<RtStateObject::SharedPtr, void*>;
        StateGraph mRtsoGraph;

        Scene::SharedPtr mpScene;
    };
}

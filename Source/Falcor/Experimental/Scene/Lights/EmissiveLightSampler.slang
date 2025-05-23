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
#include "EmissiveLightSamplerType.slangh"
__exported import Experimental.Scene.Lights.EmissiveLightSamplerInterface;

/** The host sets the _EMISSIVE_LIGHT_SAMPLER_TYPE define to select sampler.

    This code typedefs the chosen type to the type 'EmissiveLightSampler'.
    All emissive samplers adhere to the same interface, but note that the
    size of the 'EmissiveLightSampler' type may vary depending on the type.
*/

#if defined(_EMISSIVE_LIGHT_SAMPLER_TYPE) && _EMISSIVE_LIGHT_SAMPLER_TYPE == EMISSIVE_LIGHT_SAMPLER_UNIFORM
    import Experimental.Scene.Lights.EmissiveUniformSampler;
    typedef EmissiveUniformSampler EmissiveLightSampler;

#elif defined(_EMISSIVE_LIGHT_SAMPLER_TYPE) && _EMISSIVE_LIGHT_SAMPLER_TYPE == EMISSIVE_LIGHT_SAMPLER_LIGHT_BVH
    import Experimental.Scene.Lights.LightBVHSampler;
    typedef LightBVHSampler EmissiveLightSampler;

#elif defined(_EMISSIVE_LIGHT_SAMPLER_TYPE) && _EMISSIVE_LIGHT_SAMPLER_TYPE == EMISSIVE_LIGHT_SAMPLER_POWER
    import Experimental.Scene.Lights.EmissivePowerSampler;
    typedef EmissivePowerSampler EmissiveLightSampler;

#elif defined(_EMISSIVE_LIGHT_SAMPLER_TYPE)
    // Compile-time error if _EMISSIVE_LIGHT_SAMPLER_TYPE is an invalid type.
    #error _EMISSIVE_LIGHT_SAMPLER_TYPE is not set to a supported type. See EmissiveLightSamplerType.slangh.

#else
    // If _EMISSIVE_LIGHT_SAMPLER_TYPE is not defined, declare a null sampler.
    // This case happens if the user imports EmissiveLightSampler.slang but doesn't use it.
    struct NullEmissiveSampler : IEmissiveLightSampler
    {
        bool sampleLight(const float3 posW, const float3 normalW, inout SampleGenerator sg, out TriangleLightSample ls)
        {
            return false;
        }

        bool getEmissiveLightSample(const float3 posW, int lightID, float2 uv, out TriangleLightSample ls)
        {
            return false;
        }

        float evalPdf(float3 posW, float3 normalW, const TriangleHit hit)
        {
            return 0.f;
        }

        float evalPdf(const float3 posW, int lightID, float2 lightUV)
        {
            return 0.f;
        }

        int _dummy; // Dummy variable to make sure Slang doesn't remove the struct.
    };
    typedef NullEmissiveSampler EmissiveLightSampler;

#endif

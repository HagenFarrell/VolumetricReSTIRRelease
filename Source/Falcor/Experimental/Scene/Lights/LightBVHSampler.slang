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
#include "Utils/Math/MathConstants.slangh"

import Scene.Scene;
import Scene.ShadingData;
import Utils.Math.MathHelpers;
import Utils.Sampling.SampleGenerator;
import Experimental.Scene.Lights.LightBVH;
import Experimental.Scene.Lights.LightBVHSamplerSharedDefinitions;
import Experimental.Scene.Lights.LightCollection;
import Experimental.Scene.Lights.EmissiveLightSamplerHelpers;
import Experimental.Scene.Lights.EmissiveLightSamplerInterface;

// TODO: Use precise keyword at appropriate places.

// Make sure the implementation compiles even when sampler is not used.
#ifndef _ACTUAL_MAX_TRIANGLES_PER_NODE
#define _ACTUAL_MAX_TRIANGLES_PER_NODE 1
#endif

/** Emissive light sampler using a light BVH over the emissive triangles.

    The sampler implements the IEmissiveLightSampler interface (see
    EmissiveLightSamplerInterface.slang for usage information).

    The struct wraps a LightCollection that stores the pre-processed lights,
    and a LightBVH that stores the data structure used for sampling.
    The program should instantiate the struct below. See EmissiveLightSampler.slang.
*/
struct LightBVHSampler : IEmissiveLightSampler
{
    // Compile-time constants
    static const SolidAngleBoundMethod kSolidAngleBoundMethod = (SolidAngleBoundMethod)(_SOLID_ANGLE_BOUND_METHOD);

    LightBVH            _lightBVH;      ///< The BVH around the light sources.

    /** Draw a single light sample.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in,out] sg Sample generator.
        \param[out] ls Light sample. Only valid if true is returned.
        \return True if a sample was generated, false otherwise.
    */
    bool sampleLight(const float3 posW, const float3 normalW, inout SampleGenerator sg, out TriangleLightSample ls)
    {
        if (gScene.lightCollection.isEmpty()) return false;

        // Stochastically traverse the light BVH to pick a triangle.
        uint triangleIndex;
        float trianglePdf;
        float uLight = sampleNext1D(sg);
        if (!sampleLightViaBVH(posW, normalW, uLight, trianglePdf, triangleIndex)) return false;

        // Sample a point on the triangle uniformly.
        float2 u = sampleNext2D(sg);
        if (!sampleTriangle(posW, triangleIndex, u, ls)) return false;

        // The final probability density is the product of the sampling probabilities.
        ls.pdf *= trianglePdf;
        ls.pdfArea *= trianglePdf;
        return true;
    }

    bool getEmissiveLightSample(const float3 posW, int lightID, float2 uv, out TriangleLightSample ls)
    {
        if (gScene.lightCollection.getActiveTriangleCount() == 0) return false;
        uint triangleIndex = lightID;
        uint triangleCount = gScene.lightCollection.getActiveTriangleCount();
        // Sample the triangle uniformly.
        float2 u = uv;
        return sampleTriangle(posW, triangleIndex, u, ls);
    }

    /** Evaluate the PDF at a shading point given a hit point on an emissive triangle.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in] hit Triangle hit data.
        \return Probability density with respect to solid angle at the shading point.
    */
    float evalPdf(float3 posW, float3 normalW, const TriangleHit hit)
    {
        if (hit.triangleIndex == LightCollection::kInvalidIndex) return 0;

        float traversalPdf = 1.0f;
        float triangleSelectionPdf = 1.0f;

        // Evaluate PDF using the BVH.
        // Load the triangle bitmask as 2x32 bits instead of uint64_t due to driver bug.
        // TODO: Change buffer to uint64_t format and remove this workaround when http://nvbugs/2817745 is fixed.
        //uint64_t bitmask = _lightBVH.triangleBitmasks[hit.triangleIndex];
        uint2 tmp = _lightBVH.triangleBitmasks[hit.triangleIndex];
        uint64_t bitmask = ((uint64_t)tmp.y << 32) | tmp.x;

        uint leafNodeIndex;
        traversalPdf = evalBVHTraversalPdf(posW, normalW, bitmask, leafNodeIndex);
        if (traversalPdf == 0.0f) return 0.0f;

        triangleSelectionPdf = evalNodeSamplingPdf(posW, normalW, leafNodeIndex, hit.triangleIndex);
        if (triangleSelectionPdf == 0.0f) return 0.0f;

        // Compute triangle sampling probability with respect to solid angle from the shading point.
        float trianglePdf = evalTrianglePdf(posW, hit);

        // The final probability density is the product of the sampling probabilities.
        return traversalPdf * triangleSelectionPdf * trianglePdf;
    }

    float evalPdf(const float3 posW, int lightID, float2 lightUV)
    {
        return 0.f;
    }

    // Private

    /** Compute cos(max(0, a - b)) efficiently given the sine and cosine of a and b.
     */
    float cosSubClamped(float sinThetaA, float cosThetaA, float sinThetaB, float cosThetaB)
    {
        // Handle the max(0, ...): if cosThetaA > cosThetaB then thetaA <
        // thetaB and then thetaA - thetaB will be less than zero.  Return
        // cos(0) in that case.
        if (cosThetaA > cosThetaB) return 1;
        // Otherwise apply the cosine addition formula: cos(a-b) = cos(a) cos(b) + sin(a) sin(b).
        return cosThetaA * cosThetaB + sinThetaA * sinThetaB;
    }

    /** Similarly, compute sin(max(0, a - b)) efficiently given the sine and cosine of and b.
     */
    float sinSubClamped(float sinThetaA, float cosThetaA, float sinThetaB, float cosThetaB)
    {
        // Return the sine of zero if a < b.
        if (cosThetaA > cosThetaB) return 0;
        // Otherwise apply the sine addition formula: sin(a-b) = sin(a) cos(b) - cos(a) sin(b).
        return sinThetaA * cosThetaB - cosThetaA * sinThetaB;
    }

    /** Compute conservative bounds for the dot(N,L) term given an AABB.
        The function returns zero if the AABB is entirely in the negative hemisphere.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in] center AABB center.
        \param[in] extent AABB extent. The min/max corners are at center +- extent.
        \param[out] cosThetaCone Cosine of the bounding cone half angle.
        \return Conservative bound on dot(N,L) for L towards any point in the AABB.
    */
    float boundCosineTerm(const float3 posW, const float3 normalW, const float3 center, const float3 extent, out float cosThetaCone)
    {
        float3 coneDir;
        float sinThetaCone = 0.f;

        switch (kSolidAngleBoundMethod)
        {
        case SolidAngleBoundMethod::Sphere:
            // Square radius of a bounding sphere that encompasses the bounding box.
            float sqrRadius = dot(extent, extent);
            boundSphereSubtendedConeAngle(center - posW, sqrRadius, sinThetaCone, cosThetaCone);
            break;
        case SolidAngleBoundMethod::BoxToAverage:
            boundBoxSubtendedConeAngleAverage(posW, center - extent, center + extent, coneDir, sinThetaCone, cosThetaCone);
            break;
        case SolidAngleBoundMethod::BoxToCenter:
            boundBoxSubtendedConeAngleCenter(posW, center - extent, center + extent, coneDir, sinThetaCone, cosThetaCone);
            break;
        default:
            return 0.f; // Should not happen
        }

        float3 L = normalize(center - posW);
        float cosThetaL = clamp(dot(normalW, L), -1.f, 1.f);    // Cosine of the angle between normal and vector to AABB center.
        float sinThetaL = sqrt(1.f - cosThetaL * cosThetaL);
        // cos(max(0, thetaL - thetaCone)): conservative minimum angle between normal and AABB.
        return all(normalW == 0.f) ? 1.f : saturate(cosSubClamped(sinThetaL, cosThetaL, sinThetaCone, cosThetaCone));
    }

    /** Computes node importance from a given shading point.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in] nodeIndex Node index in BVH.
        \return Relative importance of this node.
    */
    float computeImportance(const float3 posW, const float3 normalW, const uint nodeIndex)
    {
        const SharedNodeAttributes nodeAttribs = _lightBVH.getNodeAttributes(nodeIndex);

    #if _DISABLE_NODE_FLUX > 0
        float flux = 1.f;
    #else
        float flux = nodeAttribs.flux;
    #endif

        // TODO: Optimize by returning squared distance.
        float distance = length(nodeAttribs.origin - posW);

        float NdotL = 1.f;
    #if _USE_BOUNDING_CONE > 0 || _USE_LIGHTING_CONE > 0
        float cosThetaBoundingCone = 0.0f;
        NdotL = boundCosineTerm(posW, normalW, nodeAttribs.origin, nodeAttribs.extent, cosThetaBoundingCone);
    #endif

    #if !(_USE_BOUNDING_CONE > 0)
        NdotL = 1.0f;
    #endif

        float orientationWeight = 1.0f;
    #if _USE_LIGHTING_CONE > 0
        // Note: coneAngle is the angle of the bounding cone for the node's dominant light directions.
        // It is _not_ the angle of the bounding cone within which light is emitted.
        // The current assumption is that all emitters are diffuse, so the actual light cone angle is PI/2 larger than coneAngle.
        // Conty Estevez and Kulla's 2018 paper uses a second cone angle (theta_e) to bound the emitted light.
        // We might want to add that to support non-diffuse emitters or switch to another representation altogether.
        float cosConeAngle = nodeAttribs.cosConeAngle;
        float3 dirToAabb = (nodeAttribs.origin - posW) / distance;          // TODO: dirToAabb won't be normalized for very short distances, as the computation of distance has a clamp.
        if (cosConeAngle != kInvalidCosConeAngle && cosConeAngle > 0.f)     // theta_o + theta_e < pi. (Note: assumes theta_e = pi/2!)
        {
            float sinConeAngle = sqrt(max(0.f, 1.f - cosConeAngle * cosConeAngle));

            float cosTheta = dot(nodeAttribs.coneDirection, -dirToAabb);    // theta = Angle between dominant light dir
            float sinTheta = sqrt(max(0.f, 1.f - cosTheta * cosTheta));

            float sinThetaBoundingCone = sqrt(max(0.f, 1 - cosThetaBoundingCone * cosThetaBoundingCone));

            // thetaPrime = max(0.0f, theta - coneAngle - thetaBoundingCone);
            // First compute the sine and cosine of max(0, theta - coneAngle).
            float cosTheta0 = cosSubClamped(sinTheta, cosTheta, sinConeAngle, cosConeAngle);
            float sinTheta0 = sinSubClamped(sinTheta, cosTheta, sinConeAngle, cosConeAngle);
            // Now we can find the cosine of max(0, (theta - coneAngle) - thetaBoundingCone):
            float cosThetaPrime = cosSubClamped(sinTheta0, cosTheta0, sinThetaBoundingCone, cosThetaBoundingCone);

            orientationWeight = max(0.f, cosThetaPrime);
        }
    #endif // _USE_LIGHTING_CONE

        // We clamp the distance to the AABB by half its radius, as
        // "[t]he center of the cluster is not representative of the emitter positions over short distances." -- Conty Estévez and Kulla, Importance Sampling of Many Lights with Adaptive Tree Splitting.
        float halfRadius = max(nodeAttribs.extent.x, max(nodeAttribs.extent.y, nodeAttribs.extent.z));
        distance = max(halfRadius, distance);

        return (flux * NdotL) * orientationWeight / (distance * distance);
    }

    /** Traverses the light BVH to select a leaf node (range of lights) to sample.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in,out] u Uniform random number. Upon return, u is still uniform and can be used for sampling among the triangles in the leaf node.
        \param[out] pdf Probabiliy of the sampled leaf node, only valid if true is returned.
        \param[out] nodeIndex The index of the sampled BVH leaf node, only valid if true is returned.
        \return True if a leaf node was sampled, false otherwise.
    */
    bool traverseTree(const float3 posW, const float3 normalW, inout float u, out float pdf, out uint nodeIndex)
    {
        pdf = 1.0f;
        nodeIndex = 0;
        bool isLeaf = _lightBVH.isLeaf(nodeIndex);

        while (!isLeaf)
        {
            uint leftNodeIndex = nodeIndex + 1;
            uint rightNodeIndex = _lightBVH.getInternalNode(nodeIndex).rightChildIdx;

            float leftNodeImportance = computeImportance(posW, normalW, leftNodeIndex);
            float rightNodeImportance = computeImportance(posW, normalW, rightNodeIndex);

            float totalImportance = leftNodeImportance + rightNodeImportance;

            // If both nodes have importance being zero, there is no need to continue.
            if (totalImportance == 0.f) return false;

            float pLeft = leftNodeImportance / totalImportance; // Probability of visiting left child.
            float pRight = 1.0f - pLeft;

            if (u < pLeft) // Traverse left node
            {
                u = u / pLeft;  // Rescale to [0,1).
                pdf *= pLeft;
                nodeIndex = leftNodeIndex;
            }
            else // Traverse right node
            {
                u = (u - pLeft) / pRight;  // Rescale to [0,1).
                pdf *= pRight;
                nodeIndex = rightNodeIndex;
            }

            isLeaf = _lightBVH.isLeaf(nodeIndex);
        }

        return true;
    }

    /** Compute the importance for the given triangle as seen from a given shading point.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in] triangleIndex The index of the triangle to compute the importance for.
        \return True if we found any triangle(s) to sample, false otherwise.
    */
    float computeTriangleImportance(const float3 posW, const float3 normalW, const uint triangleIndex)
    {
        const EmissiveTriangle tri = gScene.lightCollection.getTriangle(triangleIndex);

        // Check if we are on the back-facing side. If so the importance is zero.
        if (dot(posW - tri.posW[0], tri.normal) <= 0.f) return 0.f;

        // Compute minimum distance to triangle.
        // TODO: Use an approximation for this. The exact formulation is math heavy.
        float distSqr = max(1e-5f, computeSquaredMinDistanceToTriangle(tri.posW, posW));

        // Compute conservative bounds for dot(N,L) at the shading point.

        float NdotL = 0.0f;

        [unroll]
        // TODO: Not conservative!
        // NdotL > 0 if triangle is visible so it's safe to use, but it may be an under-estimation.
        // Consider the case where the closest point is inside the triangle and all vertices are far away.
        // Their dot products will be small, but the dot product to a sample inside can be larger.
        for (uint i = 0; i < 3; ++i)
        {
            NdotL = max(NdotL, dot(normalW, normalize(tri.posW[i] - posW)));
        }
        NdotL = saturate(NdotL);

        if (all(normalW == 0.f)) NdotL = 1.f;

        return NdotL / distSqr;
    }

    /** Pick a triangle in a leaf node to sample.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in] nodeIndex The index of the BVH leaf node.
        \param[in] u Uniform random number.
        \param[out] pdf Probabiliy of the sampled triangle, only valid if true is returned.
        \param[out] triangleIndex Index of the sampled triangle, only valid if true is returned.
        \return True if a triangle was sampled, false otherwise.
    */
    bool pickTriangle(const float3 posW, const float3 normalW, const uint nodeIndex, const float u, out float pdf, out uint triangleIndex)
    {
        const LeafNode node = _lightBVH.getLeafNode(nodeIndex);

    #if _USE_UNIFORM_TRIANGLE_SAMPLING
        uint idx = min((uint)(u * node.triangleCount), node.triangleCount - 1); // Safety precaution in case u == 1.0 (it shouldn't be).
        triangleIndex = _lightBVH.getNodeTriangleIndex(node, idx);
        pdf = 1.0f / (float)node.triangleCount;
        return true;
    #else
        float pdfs[_ACTUAL_MAX_TRIANGLES_PER_NODE];
        float totalImportance = 0.0f;

        for (uint i = 0; i < node.triangleCount; ++i)
        {
            uint triIdx = _lightBVH.getNodeTriangleIndex(node, i);
            pdfs[i] = computeTriangleImportance(posW, normalW, triIdx);
            totalImportance += pdfs[i];
        }

        // If the total importance is zero, none of the triangles matter so just bail out.
        if (totalImportance == 0.0f) return false;

        float uScaled = u * totalImportance;
        float cdf = 0.0f;

        uint idx = 0;
        for (; idx < node.triangleCount; ++idx)
        {
            cdf += pdfs[idx];
            if (uScaled < cdf) break;
        }

        idx = min(idx, node.triangleCount - 1); // Safety precaution in case uScaled == cdf (it shouldn't be).
        triangleIndex = _lightBVH.getNodeTriangleIndex(node, idx);
        pdf = pdfs[idx] / totalImportance;
        return true;
    #endif
    }

    /** Samples a light using the BVH.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in] u Uniform random number.
        \param[out] pdf Probabiliy of the sampled triangle, only valid if true is returned.
        \param[out] triangleIndex Index of the sampled triangle, only valid if true is returned.
        \return True if a triangle was sampled, false otherwise.
    */
    bool sampleLightViaBVH(const float3 posW, const float3 normalW, float u, out float pdf, out uint triangleIndex)
    {
        // Traverse BVH to select a leaf node with N triangles based on estimated probabilities during traversal.
        float leafPdf;
        uint leafNodeIndex;
        if (!traverseTree(posW, normalW, u, leafPdf, leafNodeIndex)) return false;

        // Within the selected leaf, pick one out of the N triangles to sample.
        float trianglePdf;
        if (!pickTriangle(posW, normalW, leafNodeIndex, u, trianglePdf, triangleIndex)) return false;

        pdf = leafPdf * trianglePdf;
        return true;
    }

    /** Returns the PDF of selecting the specified leaf node by traversing the tree.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in] bitmask The bit pattern describing at each level which child was chosen in order to reach the specifide leaf node.
        \param[out] nodeIndex The node index at which the given leaf node is located.
    */
    float evalBVHTraversalPdf(const float3 posW, const float3 normalW, uint64_t bitmask, out uint nodeIndex)
    {
        float traversalPdf = 1.0f;
        nodeIndex = 0;
        bool isLeaf = _lightBVH.isLeaf(nodeIndex);

        while (!isLeaf)
        {
            uint leftNodeIndex = nodeIndex + 1;
            uint rightNodeIndex = _lightBVH.getInternalNode(nodeIndex).rightChildIdx;

            float leftNodeImportance = computeImportance(posW, normalW, leftNodeIndex);
            float rightNodeImportance = computeImportance(posW, normalW, rightNodeIndex);

            float totalImportance = leftNodeImportance + rightNodeImportance;
            if (totalImportance == 0.f) return 0.0f;

            float pLeft = leftNodeImportance / totalImportance; // Probability of visiting left child.
            float pRight = 1.0f - pLeft;

            bool chooseLeftNode = (bitmask & 0x1) == 0;
            if (chooseLeftNode) // Traverse left node
            {
                traversalPdf *= pLeft;
                nodeIndex = leftNodeIndex;
            }
            else // Traverse right node
            {
                traversalPdf *= pRight;
                nodeIndex = rightNodeIndex;
            }

            bitmask >>= 1;
            isLeaf = _lightBVH.isLeaf(nodeIndex);
        }

        return traversalPdf;
    }

    /** Returns the PDF of selecting the specified triangle inside the specified leaf node as seen from a given shading point.
        \param[in] posW Shading point in world space.
        \param[in] normalW Normal at the shading point in world space.
        \param[in] nodeIndex The index at which the given leaf node is located.
        \param[in] triangleIndex The global index of the triangle that was selected.
        \return Probability density for selecting the given triangle.
    */
    float evalNodeSamplingPdf(const float3 posW, const float3 normalW, const uint nodeIndex, const uint triangleIndex)
    {
        const LeafNode node = _lightBVH.getLeafNode(nodeIndex);

    #if _USE_UNIFORM_TRIANGLE_SAMPLING == 1
        return 1.0f / ((float)node.triangleCount);
    #else
        float triangleImportance = 0.0f;
        float totalImportance = 0.0f;
        for (uint i = 0; i < node.triangleCount; ++i)
        {
            uint localTriangleIndex = _lightBVH.getNodeTriangleIndex(node, i);
            float importance = computeTriangleImportance(posW, normalW, localTriangleIndex);
            if (triangleIndex == localTriangleIndex)
            {
                triangleImportance = importance;
            }
            totalImportance += importance;
        }

        // If the total importance is 0, none of the triangles matter so just bail out.
        if (totalImportance == 0.0f)
        {
            return 0.0f;
        }

        return triangleImportance / totalImportance;
    #endif
    }
};

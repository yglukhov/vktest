import sets
import system/ansi_c

# import nimgl/vulkan
import nimgl/glfw, nimgl/glfw/native
import vulkan

when defined(windows):
  from winlean import Handle
  from os import getEnv
  {.passl: "-L" & getEnv("USERPROFILE") & "\\scoop\\apps\\vulkan\\current\\Lib".}
  {.passl: "-lvulkan-1".}
else:
  {.passl: "-lvulkan".}

type
  Engine = object
    instance: VkInstance
    physicalDevice: VkPhysicalDevice
    device: VkDevice
    graphicsQueue: VkQueue
    surface: VkSurfaceKHR
    presentQueue: VkQueue
    swapChain: VkSwapchainKHR
    swapChainImages: seq[VkImage]
    swapChainImageFormat: VkFormat
    swapChainExtent: VkExtent2D
    swapChainImageViews: seq[VkImageView]
    renderPass: VkRenderPass
    pipelineLayout: VkPipelineLayout
    graphicsPipeline: VkPipeline
    swapChainFramebuffers: seq[VkFramebuffer]
    commandPool: VkCommandPool
    commandBuffers: seq[VkCommandBuffer]
    imageAvailableSemaphore: VkSemaphore
    renderFinishedSemaphore: VkSemaphore
    availableValidationLayers: seq[cstring]

  QueueFamilyIndices = object
    graphicsFamily: int32
    presentFamily: int32

  SwapChainSupportDetails = object
    capabilities: VkSurfaceCapabilitiesKHR
    formats: seq[VkSurfaceFormatKHR]
    presentModes: seq[VkPresentModeKHR]

const
  enableValidationLayers = not defined(release)
  # validationLayers = ["VK_LAYER_KHRONOS_validation"]
  desiredValidationLayers = ["VK_LAYER_LUNARG_standard_validation".cstring]

let deviceExtensions = [vkKhrSwapchainExtensionName.cstring]

converter toBool(v: VkBool32): bool {.inline.} = v != 0
converter toVkBool32(v: bool): VkBool32 {.inline.} = VkBool32(v)

var
  window: GLFWWindow

proc isNil(v: VkPhysicalDevice): bool =
  cast[int64](v) == 0

proc toString(chars: openArray[char]): string =
  result = ""
  for c in chars:
    if c != '\0':
      result.add(c)

proc initWindow(e: var Engine) =
  if not glfwInit():
    quit("failed to init glfw")

  glfwWindowHint(GLFWClientApi, GLFWNoApi)
  glfwWindowHint(GLFWResizable, GLFWFalse)

  window = glfwCreateWindow(800, 600)

  # if not vkInit():
  #   quit("failed to load vulkan")

proc drawFrame(e: Engine) =
  var imageIndex: uint32
  discard vkAcquireNextImageKHR(e.device, e.swapChain, uint64.high, e.imageAvailableSemaphore, 0, addr imageIndex)

  var submitInfo: VkSubmitInfo
  submitInfo.sType = VkStructureType.submitInfo

  var waitSemaphores = [e.imageAvailableSemaphore]
  var waitStage = cast[VkPipelineStageFlags](VkPipelineStageFlagBits.colorAttachmentOutput)
  submitInfo.waitSemaphoreCount = waitSemaphores.len.uint32
  submitInfo.pWaitSemaphores = addr waitSemaphores[0]
  submitInfo.pWaitDstStageMask = addr waitStage

  submitInfo.commandBufferCount = 1
  submitInfo.pCommandBuffers = unsafeAddr e.commandBuffers[imageIndex]

  var signalSemaphores = [e.renderFinishedSemaphore]
  submitInfo.signalSemaphoreCount = signalSemaphores.len.uint32
  submitInfo.pSignalSemaphores = addr signalSemaphores[0]

  if vkQueueSubmit(e.graphicsQueue, 1, addr submitInfo, 0) != success:
    raise newException(ValueError, "failed to submit draw command buffer")

  var presentInfo: VkPresentInfoKHR
  presentInfo.sType = VkStructureType.presentInfoKHR
  presentInfo.waitSemaphoreCount = signalSemaphores.len.uint32
  presentInfo.pWaitSemaphores = addr signalSemaphores[0]

  var swapChains = [e.swapChain]
  presentInfo.swapchainCount = swapChains.len.uint32
  presentInfo.pSwapchains = addr swapChains[0]
  presentInfo.pImageIndices = addr imageIndex
  presentInfo.pResults = nil # Optional
  discard vkQueuePresentKHR(e.presentQueue, addr presentInfo)
  discard vkQueueWaitIdle(e.presentQueue)


proc mainLoop(e: var Engine) =
  while not window.windowShouldClose():
    glfwPollEvents()
    e.drawFrame()
    # break

  discard vkDeviceWaitIdle(e.device)

proc cleanUp(e: var Engine) =
  vkDestroySemaphore(e.device, e.renderFinishedSemaphore, nil)
  vkDestroySemaphore(e.device, e.imageAvailableSemaphore, nil)
  vkDestroyCommandPool(e.device, e.commandPool, nil)
  for framebuffer in e.swapChainFramebuffers:
    vkDestroyFramebuffer(e.device, framebuffer, nil)

  vkDestroyPipeline(e.device, e.graphicsPipeline, nil)
  vkDestroyPipelineLayout(e.device, e.pipelineLayout, nil)
  vkDestroyRenderPass(e.device, e.renderPass, nil)

  for imageView in e.swapChainImageViews:
    vkDestroyImageView(e.device, imageView, nil)

  vkDestroySwapchainKHR(e.device, e.swapChain, nil)
  vkDestroyDevice(e.device, nil)
  vkDestroySurfaceKHR(e.instance, e.surface, nil)
  vkDestroyInstance(e.instance, nil)
  window.destroyWindow()
  glfwTerminate()

when enableValidationLayers:
  proc getAvailableValidationLayers(): seq[cstring] =
    var layerCount: uint32
    discard vkEnumerateInstanceLayerProperties(addr layerCount, nil)

    var availableLayers = newSeq[VkLayerProperties](layerCount)
    if layerCount != 0:
      discard vkEnumerateInstanceLayerProperties(addr layerCount, addr availableLayers[0]);

    for layerName in desiredValidationLayers:
      var layerFound = false
      for layerProperties in availableLayers:
        echo "layerProperties.layerName ", cstring(unsafeAddr layerProperties.layerName)
        if c_strcmp(layerName, unsafeAddr layerProperties.layerName) == 0:
          result.add(layerName)
          break

proc getRequiredExtensions(): seq[cstring] =
  var glfwExtensionCount: uint32
  let glfwExtensions = glfwGetRequiredInstanceExtensions(glfwExtensionCount.addr)
  result = newSeqOfCap[cstring](glfwExtensionCount + 1)
  for i in 0 ..< glfwExtensionCount: result.add(glfwExtensions[i])

  when defined(windows):
    result.add(vkKhrWin32SurfaceExtensionName)
  else:
    result.add(vkKhrXlibSurfaceExtensionName)

  when enableValidationLayers:
    result.add("VK_EXT_debug_utils")

proc checkErr(res: VkResult, msg: string) =
  if res != success:
    raise newException(ValueError, msg & ": " & $res)

proc createInstance(e: var Engine) =
  when defined(macosx):
    let vkVersion = vkApiVersion1_0.uint32
  else:
    let vkVersion = vkMakeVersion(1, 1, 0).uint32
  var appInfo: VkApplicationInfo
  appInfo.sType = applicationInfo
  appInfo.pApplicationName = "NimGL Vulkan Example"
  appInfo.applicationVersion = vkMakeVersion(1, 0, 0)
  appInfo.pEngineName = "No Engine"
  appInfo.engineVersion = vkMakeVersion(1, 0, 0)
  appInfo.apiVersion = vkVersion

  let requiredExtensions = getRequiredExtensions()

  var createInfo: VkInstanceCreateInfo
  createInfo.sType = instanceCreateInfo
  createInfo.pApplicationInfo = appInfo.addr
  createInfo.enabledExtensionCount = requiredExtensions.len.uint32
  createInfo.ppEnabledExtensionNames = cast[cstringArray](unsafeAddr requiredExtensions[0])

  when enableValidationLayers:
    e.availableValidationLayers = getAvailableValidationLayers()
    if e.availableValidationLayers.len != desiredValidationLayers.len:
      echo "WARNING: Vulkan validation layers requested, but not available. Install vulkan development libraries, or compile in release mode."

    if e.availableValidationLayers.len != 0:
      createInfo.enabledLayerCount = e.availableValidationLayers.len.uint32
      createInfo.ppEnabledLayerNames = cast[cstringArray](addr e.availableValidationLayers[0])

  checkErr vkCreateInstance(createInfo.addr, nil, e.instance.addr), "creating instance"

proc setupDebugMessenger(e: var Engine) =
  discard

proc isComplete(qf: QueueFamilyIndices): bool =
  qf.graphicsFamily >= 0 and qf.presentFamily >= 0

proc findQueueFamilies(e: Engine, device: VkPhysicalDevice): QueueFamilyIndices =
  result.graphicsFamily = -1

  var queueFamilyCount: uint32
  vkGetPhysicalDeviceQueueFamilyProperties(device, addr queueFamilyCount, nil)
  var queueFamilies = newSeq[VkQueueFamilyProperties](queueFamilyCount)
  if queueFamilyCount != 0:
    vkGetPhysicalDeviceQueueFamilyProperties(device, addr queueFamilyCount, addr queueFamilies[0])
  for i, queueFamily in queueFamilies:
    if (cast[uint32](queueFamily.queueFlags) and cast[uint32](VkQueueFlagBits.graphics)) != 0:
      result.graphicsFamily = i.int32
    var presentSupport: VkBool32
    discard vkGetPhysicalDeviceSurfaceSupportKHR(device, i.uint32, e.surface, addr presentSupport)
    if presentSupport:
      result.presentFamily = i.int32
    if result.isComplete: break

proc querySwapChainSupport(e: Engine, device: VkPhysicalDevice): SwapChainSupportDetails =
  discard vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, e.surface, addr result.capabilities)

  var formatCount: uint32
  discard vkGetPhysicalDeviceSurfaceFormatsKHR(device, e.surface, addr formatCount, nil)
  if formatCount != 0:
    result.formats.setLen(formatCount)
    discard vkGetPhysicalDeviceSurfaceFormatsKHR(device, e.surface, addr formatCount, addr result.formats[0])

  var presentModeCount: uint32
  discard vkGetPhysicalDeviceSurfacePresentModesKHR(device, e.surface, addr presentModeCount, nil)
  if presentModeCount != 0:
    result.presentModes.setLen(presentModeCount)
    discard vkGetPhysicalDeviceSurfacePresentModesKHR(device, e.surface, addr presentModeCount, addr result.presentModes[0])


proc checkDeviceExtensionSupport(e: Engine, device: VkPhysicalDevice): bool =
  var extensionCount: uint32
  discard vkEnumerateDeviceExtensionProperties(device, nil, addr extensionCount, nil)
  var availableExtensions = newSeq[VkExtensionProperties](extensionCount)
  if extensionCount != 0:
    discard vkEnumerateDeviceExtensionProperties(device, nil, addr extensionCount, addr availableExtensions[0])
  var requiredExtensions = toHashSet(deviceExtensions)
  for extension in availableExtensions:
    requiredExtensions.excl(extension.extensionName.unsafeAddr.cstring)
  requiredExtensions.len == 0

proc chooseSwapSurfaceFormat(availableFormats: openarray[VkSurfaceFormatKHR]): VkSurfaceFormatKHR =
  for availableFormat in availableFormats:
    if availableFormat.format == b8g8r8a8Unorm and availableFormat.colorSpace == srgbNonlinearKhr:
      return availableFormat
  return availableFormats[0]

proc chooseSwapPresentMode(availablePresentModes: openarray[VkPresentModeKHR]): VkPresentModeKHR =
  for availablePresentMode in availablePresentModes:
    if availablePresentMode == VkPresentModeKHR.mailbox:
      return availablePresentMode
  return VkPresentModeKHR.fifo

const
  WIDTH = 800
  HEIGHT = 600

proc chooseSwapExtent(capabilities: VkSurfaceCapabilitiesKHR): VkExtent2D =
  if capabilities.currentExtent.width != uint32.high:
    return capabilities.currentExtent
  else:
    result = VkExtent2D(width: WIDTH, height: HEIGHT)
    result.width = clamp(result.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width)
    result.height = clamp(result.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)

proc rateDeviceSuitability(e: Engine, device: VkPhysicalDevice): int =
  proc checkSwapChainSupport(e: Engine, device: VkPhysicalDevice): bool {.inline.} =
    let swapChainSupport = e.querySwapChainSupport(device)
    swapChainSupport.formats.len != 0 and swapChainSupport.presentModes.len != 0

  var deviceProperties: VkPhysicalDeviceProperties
  var deviceFeatures: VkPhysicalDeviceFeatures
  echo "device: ", cast[cstring](addr deviceProperties.deviceName)
  vkGetPhysicalDeviceProperties(device, addr deviceProperties)
  vkGetPhysicalDeviceFeatures(device, addr deviceFeatures)


  if not (e.findQueueFamilies(device).isComplete and e.checkDeviceExtensionSupport(device) and e.checkSwapChainSupport(device)):
    return 0


  result = 1

  if deviceProperties.deviceType == discreteGpu:
    result += 1000

  result += deviceProperties.limits.maxImageDimension2D.int
  echo "rate: ", result

proc pickPhysicalDevice(e: var Engine) =
  var deviceCount: uint32
  discard vkEnumeratePhysicalDevices(e.instance, addr deviceCount, nil)
  if deviceCount == 0:
    raise newException(ValueError, "failed to find GPUs with Vulkan support")
  var devices = newSeq[VkPhysicalDevice](deviceCount)
  var scores = newSeq[int](deviceCount)
  discard vkEnumeratePhysicalDevices(e.instance, addr deviceCount, addr devices[0])
  for i, device in devices:
    scores[i] = e.rateDeviceSuitability(device)

  var maxScore, maxScoreI: int
  for i, score in scores:
    if score > maxScore:
      maxScore = score
      maxScoreI = i

  if maxScore == 0:
    raise newException(ValueError, "failed to find a suitable GPU")

  e.physicalDevice = devices[maxScoreI]

proc createLogicalDevice(e: var Engine) =
  var indices = e.findQueueFamilies(e.physicalDevice)
  var queuePriority: cfloat = 1.0

  let uniqueQueueFamilies = toHashSet([indices.graphicsFamily, indices.presentFamily])
  var queueCreateInfos = newSeq[VkDeviceQueueCreateInfo]()
  for queueFamily in uniqueQueueFamilies:
    var queueCreateInfo: VkDeviceQueueCreateInfo
    queueCreateInfo.sType = deviceQueueCreateInfo
    queueCreateInfo.queueFamilyIndex = queueFamily.uint32
    queueCreateInfo.queueCount = 1
    queueCreateInfo.pQueuePriorities = addr queuePriority
    queueCreateInfos.add(queueCreateInfo)

  var deviceFeatures: VkPhysicalDeviceFeatures

  var createInfo: VkDeviceCreateInfo
  createInfo.sType = deviceCreateInfo
  createInfo.pQueueCreateInfos = addr queueCreateInfos[0]
  createInfo.queueCreateInfoCount = queueCreateInfos.len.uint32

  createInfo.pEnabledFeatures = addr deviceFeatures

  createInfo.enabledExtensionCount = deviceExtensions.len.uint32
  createInfo.ppEnabledExtensionNames = cast[cstringArray](unsafeAddr deviceExtensions[0])

  when enableValidationLayers:
    if e.availableValidationLayers.len != 0:
      createInfo.enabledLayerCount = e.availableValidationLayers.len.uint32
      createInfo.ppEnabledLayerNames = cast[cstringArray](addr e.availableValidationLayers[0])

  if vkCreateDevice(e.physicalDevice, addr createInfo, nil, addr e.device) != success:
    raise newException(ValueError, "failed to create logical device")

  vkGetDeviceQueue(e.device, indices.graphicsFamily.uint32, 0, addr e.graphicsQueue)
  vkGetDeviceQueue(e.device, indices.presentFamily.uint32, 0, addr e.presentQueue)

proc createSurface(e: var Engine) =
  when defined(windows):
    var createInfo: VkWin32SurfaceCreateInfoKHR
    createInfo.sType = win32SurfaceCreateInfoKHR
    createInfo.hwnd = cast[Handle](getWin32Window(window))
    createInfo.hinstance = 0 #GetModuleHandle(nil)

    let ret = vkCreateWin32SurfaceKHR(e.instance, addr createInfo, nil, addr e.surface)
  else:
    var createInfo: VkXlibSurfaceCreateInfoKHR
    createInfo.sType = xlibSurfaceCreateInfoKHR
    createInfo.dpy = glfwGetX11Display()
    createInfo.window = getX11Window(window)

    let ret = vkCreateXlibSurfaceKHR(e.instance, addr createInfo, nil, addr e.surface)

  if ret != success:
    raise newException(ValueError, "failed to create window surface: " & $ret)

proc createSwapChain(e: var Engine) =
  let swapChainSupport = e.querySwapChainSupport(e.physicalDevice)
  let surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats)
  let presentMode = chooseSwapPresentMode(swapChainSupport.presentModes)
  let extent = chooseSwapExtent(swapChainSupport.capabilities)
  var imageCount = swapChainSupport.capabilities.minImageCount + 1
  if swapChainSupport.capabilities.maxImageCount != 0 and imageCount > swapChainSupport.capabilities.maxImageCount:
    imageCount = swapChainSupport.capabilities.maxImageCount

  var createInfo: VkSwapchainCreateInfoKHR
  createInfo.sType = swapchainCreateInfoKHR
  createInfo.surface = e.surface

  createInfo.minImageCount = imageCount
  createInfo.imageFormat = surfaceFormat.format
  createInfo.imageColorSpace = surfaceFormat.colorSpace
  createInfo.imageExtent = extent
  createInfo.imageArrayLayers = 1
  createInfo.imageUsage = cast[uint32](VkImageUsageFlagBits.colorAttachment)

  let indices = e.findQueueFamilies(e.physicalDevice)
  var queueFamilyIndices = [indices.graphicsFamily, indices.presentFamily]
  if indices.graphicsFamily != indices.presentFamily:
    createInfo.imageSharingMode = VkSharingMode.concurrent
    createInfo.queueFamilyIndexCount = 2
    createInfo.pQueueFamilyIndices = cast[ptr uint32](addr queueFamilyIndices[0])
  else:
    createInfo.imageSharingMode = VkSharingMode.exclusive

  createInfo.preTransform = swapChainSupport.capabilities.currentTransform
  createInfo.compositeAlpha = VkCompositeAlphaFlagBitsKHR.opaque
  createInfo.presentMode = presentMode
  createInfo.clipped = 1

  if vkCreateSwapchainKHR(e.device, addr createInfo, nil, addr e.swapChain) != success:
    raise newException(ValueError, "failed to create swap chain")

  discard vkGetSwapchainImagesKHR(e.device, e.swapChain, addr imageCount, nil)
  e.swapChainImages.setLen(imageCount)
  if imageCount != 0:
    discard vkGetSwapchainImagesKHR(e.device, e.swapChain, addr imageCount, addr e.swapChainImages[0])

  e.swapChainImageFormat = surfaceFormat.format
  e.swapChainExtent = extent

proc createImageViews(e: var Engine) =
  e.swapChainImageViews.setLen(e.swapChainImages.len)
  var createInfo: VkImageViewCreateInfo
  createInfo.sType = imageViewCreateInfo
  createInfo.viewType = VkImageViewType.twoDee
  createInfo.format = e.swapChainImageFormat
  createInfo.components.r = VkComponentSwizzle.identity
  createInfo.components.g = VkComponentSwizzle.identity
  createInfo.components.b = VkComponentSwizzle.identity
  createInfo.components.a = VkComponentSwizzle.identity
  createInfo.subresourceRange.aspectMask = cast[VkImageAspectFlags](VkImageAspectFlagBits.color)
  createInfo.subresourceRange.baseMipLevel = 0
  createInfo.subresourceRange.levelCount = 1
  createInfo.subresourceRange.baseArrayLayer = 0
  createInfo.subresourceRange.layerCount = 1

  for i in 0 .. e.swapChainImages.high:
    createInfo.image = e.swapChainImages[i]
    if vkCreateImageView(e.device, addr createInfo, nil, addr e.swapChainImageViews[i]) != success:
      raise newException(ValueError, "failed to create image views")

proc createShaderModule(e: Engine, code: string): VkShaderModule =
  var createInfo: VkShaderModuleCreateInfo
  createInfo.sType = shaderModuleCreateInfo
  createInfo.codeSize = code.len
  createInfo.pCode = cast[ptr uint32](unsafeAddr code[0])
  if vkCreateShaderModule(e.device, addr createInfo, nil, addr result) != success:
    raise newException(ValueError, "failed to create shader module")

proc createRenderPass(e: var Engine) =
  var colorAttachment: VkAttachmentDescription
  colorAttachment.format = e.swapChainImageFormat
  colorAttachment.samples = VkSampleCountFlagBits.one
  colorAttachment.loadOp = VkAttachmentLoadOp.opClear
  colorAttachment.storeOp = VkAttachmentStoreOp.opStore
  colorAttachment.stencilLoadOp = VkAttachmentLoadOp.opDontCare
  colorAttachment.stencilStoreOp = VkAttachmentStoreOp.opDontCare
  colorAttachment.initialLayout = VkImageLayout.undefined
  colorAttachment.finalLayout = VkImageLayout.presentSrcKHR

  var colorAttachmentRef: VkAttachmentReference
  colorAttachmentRef.attachment = 0
  colorAttachmentRef.layout = VkImageLayout.colorAttachmentOptimal

  var subpass: VkSubpassDescription
  subpass.pipelineBindPoint = VkPipelineBindPoint.graphics
  subpass.colorAttachmentCount = 1
  subpass.pColorAttachments = addr colorAttachmentRef

  var dependency: VkSubpassDependency
  dependency.srcSubpass = vkSubpassExternal
  dependency.dstSubpass = 0
  dependency.srcStageMask = cast[VkPipelineStageFlags](VkPipelineStageFlagBits.colorAttachmentOutput)
  dependency.srcAccessMask = 0

  dependency.dstStageMask = cast[VkPipelineStageFlags](VkPipelineStageFlagBits.colorAttachmentOutput)
  dependency.dstAccessMask = cast[uint32](VkAccessFlagBits.colorAttachmentRead) or cast[uint32](VkAccessFlagBits.colorAttachmentWrite)


  var renderPassInfo: VkRenderPassCreateInfo
  renderPassInfo.sType = renderPassCreateInfo
  renderPassInfo.attachmentCount = 1
  renderPassInfo.pAttachments = addr colorAttachment
  renderPassInfo.subpassCount = 1
  renderPassInfo.pSubpasses = addr subpass
  renderPassInfo.dependencyCount = 1
  renderPassInfo.pDependencies = addr dependency

  if vkCreateRenderPass(e.device, addr renderPassInfo, nil, addr e.renderPass) != success:
    raise newException(ValueError, "failed to create render pass")

proc createGraphicsPipeline(e: var Engine) =
  let vertShaderCode = readFile("shader.vert.spv")
  let fragShaderCode = readFile("shader.frag.spv")

  let vertShaderModule = e.createShaderModule(vertShaderCode)
  let fragShaderModule = e.createShaderModule(fragShaderCode)

  var vertShaderStageInfo: VkPipelineShaderStageCreateInfo
  vertShaderStageInfo.sType = pipelineShaderStageCreateInfo
  vertShaderStageInfo.stage = VkShaderStageFlagBits.vertex
  vertShaderStageInfo.module = vertShaderModule
  vertShaderStageInfo.pName = "main"

  var fragShaderStageInfo: VkPipelineShaderStageCreateInfo
  fragShaderStageInfo.sType = pipelineShaderStageCreateInfo
  fragShaderStageInfo.stage = VkShaderStageFlagBits.fragment
  fragShaderStageInfo.module = fragShaderModule
  fragShaderStageInfo.pName = "main"

  var shaderStages = [vertShaderStageInfo, fragShaderStageInfo]

  var vertexInputInfo: VkPipelineVertexInputStateCreateInfo
  vertexInputInfo.sType = pipelineVertexInputStateCreateInfo
  vertexInputInfo.vertexBindingDescriptionCount = 0
  vertexInputInfo.pVertexBindingDescriptions = nil
  vertexInputInfo.vertexAttributeDescriptionCount = 0
  vertexInputInfo.pVertexAttributeDescriptions = nil

  var inputAssembly: VkPipelineInputAssemblyStateCreateInfo
  inputAssembly.sType = pipelineInputAssemblyStateCreateInfo
  inputAssembly.topology = VkPrimitiveTopology.triangleList
  inputAssembly.primitiveRestartEnable = 0

  var viewport: VkViewport
  viewport.x = 0
  viewport.y = 0
  viewport.width = e.swapChainExtent.width.cfloat
  viewport.height = e.swapChainExtent.height.cfloat
  viewport.minDepth = 0
  viewport.maxDepth = 1

  var scissor: VkRect2D
  scissor.offset = VkOffset2D(x: 0, y: 0)
  scissor.extent = e.swapChainExtent

  var viewportState: VkPipelineViewportStateCreateInfo
  viewportState.sType = pipelineViewportStateCreateInfo
  viewportState.viewportCount = 1
  viewportState.pViewports = addr viewport
  viewportState.scissorCount = 1
  viewportState.pScissors = addr scissor

  var rasterizer: VkPipelineRasterizationStateCreateInfo
  rasterizer.sType = pipelineRasterizationStateCreateInfo
  rasterizer.depthClampEnable = 0
  rasterizer.rasterizerDiscardEnable = 0
  rasterizer.polygonMode = VkPolygonMode.fill
  rasterizer.lineWidth = 1.0
  rasterizer.cullMode = cast[VkCullModeFlags](VkCullModeFlagBits.back)
  rasterizer.frontFace = VkFrontFace.clockwise
  rasterizer.depthBiasEnable = 0
  rasterizer.depthBiasConstantFactor = 0.0
  rasterizer.depthBiasClamp = 0.0
  rasterizer.depthBiasSlopeFactor = 0.0

  var multisampling: VkPipelineMultisampleStateCreateInfo
  multisampling.sType = pipelineMultisampleStateCreateInfo;
  multisampling.sampleShadingEnable = false
  multisampling.rasterizationSamples = VkSampleCountFlagBits.one
  multisampling.minSampleShading = 1.0 # Optional
  multisampling.pSampleMask = nil # Optional
  multisampling.alphaToCoverageEnable = false # Optional
  multisampling.alphaToOneEnable = false # Optional

  var colorBlendAttachment: VkPipelineColorBlendAttachmentState
  colorBlendAttachment.colorWriteMask = cast[VkColorComponentFlags](
      cast[uint32](VkColorComponentFlagBits.r) or
      cast[uint32](VkColorComponentFlagBits.g) or
      cast[uint32](VkColorComponentFlagBits.b) or
      cast[uint32](VkColorComponentFlagBits.a))
  colorBlendAttachment.blendEnable = false;
  colorBlendAttachment.srcColorBlendFactor = VkBlendFactor.one # Optional
  colorBlendAttachment.dstColorBlendFactor = VkBlendFactor.zero # Optional
  colorBlendAttachment.colorBlendOp = VkBlendOp.opAdd # Optional
  colorBlendAttachment.srcAlphaBlendFactor = VkBlendFactor.one # Optional
  colorBlendAttachment.dstAlphaBlendFactor = VkBlendFactor.zero # Optional
  colorBlendAttachment.alphaBlendOp = VkBlendOp.opAdd # Optional

  var colorBlending: VkPipelineColorBlendStateCreateInfo
  colorBlending.sType = pipelineColorBlendStateCreateInfo;
  colorBlending.logicOpEnable = false
  colorBlending.logicOp = VkLogicOp.opCopy # Optional
  colorBlending.attachmentCount = 1
  colorBlending.pAttachments = addr colorBlendAttachment
  colorBlending.blendConstants[0] = 0.0 # Optional
  colorBlending.blendConstants[1] = 0.0 # Optional
  colorBlending.blendConstants[2] = 0.0 # Optional
  colorBlending.blendConstants[3] = 0.0 # Optional

  var dynamicStates = [ VkDynamicState.viewport, VkDynamicState.lineWidth ]

  var dynamicState: VkPipelineDynamicStateCreateInfo
  dynamicState.sType = pipelineDynamicStateCreateInfo
  dynamicState.dynamicStateCount = 2
  dynamicState.pDynamicStates = addr dynamicStates[0]


  var pipelineLayoutInfo: VkPipelineLayoutCreateInfo
  pipelineLayoutInfo.sType = pipelineLayoutCreateInfo
  pipelineLayoutInfo.setLayoutCount = 0 # Optional
  pipelineLayoutInfo.pSetLayouts = nil # Optional
  pipelineLayoutInfo.pushConstantRangeCount = 0 # Optional
  pipelineLayoutInfo.pPushConstantRanges = nil # Optional

  if vkCreatePipelineLayout(e.device, addr pipelineLayoutInfo, nil, addr e.pipelineLayout) != success:
    raise newException(ValueError, "failed to create pipeline layout")

  var pipelineInfo: VkGraphicsPipelineCreateInfo
  pipelineInfo.sType = graphicsPipelineCreateInfo
  pipelineInfo.stageCount = 2
  pipelineInfo.pStages = addr shaderStages[0]

  pipelineInfo.pVertexInputState = addr vertexInputInfo
  pipelineInfo.pInputAssemblyState = addr inputAssembly
  pipelineInfo.pViewportState = addr viewportState
  pipelineInfo.pRasterizationState = addr rasterizer
  pipelineInfo.pMultisampleState = addr multisampling
  pipelineInfo.pDepthStencilState = nil # Optional
  pipelineInfo.pColorBlendState = addr colorBlending
  pipelineInfo.pDynamicState = nil # Optional
  pipelineInfo.layout = e.pipelineLayout
  pipelineInfo.renderPass = e.renderPass
  pipelineInfo.subpass = 0

#  pipelineInfo.basePipelineHandle = nil # Optional
  pipelineInfo.basePipelineIndex = -1 # Optional

  if vkCreateGraphicsPipelines(e.device, 0, 1, addr pipelineInfo, nil, addr e.graphicsPipeline) != success:
    raise newException(ValueError, "failed to create graphics pipeline")

  vkDestroyShaderModule(e.device, fragShaderModule, nil)
  vkDestroyShaderModule(e.device, vertShaderModule, nil)

proc createFramebuffers(e: var Engine) =
  e.swapChainFramebuffers.setLen(e.swapChainImageViews.len)
  var framebufferInfo: VkFramebufferCreateInfo
  framebufferInfo.sType = framebufferCreateInfo
  framebufferInfo.renderPass = e.renderPass
  framebufferInfo.attachmentCount = 1
  framebufferInfo.width = e.swapChainExtent.width
  framebufferInfo.height = e.swapChainExtent.height
  framebufferInfo.layers = 1

  for i in 0 .. e.swapChainImageViews.high:
    framebufferInfo.pAttachments = addr e.swapChainImageViews[i]
    if vkCreateFramebuffer(e.device, addr framebufferInfo, nil, addr e.swapChainFramebuffers[i]) != success:
      raise newException(ValueError, "failed to create framebuffer")

proc createCommandPool(e: var Engine) =
  let queueFamilyIndices = e.findQueueFamilies(e.physicalDevice)
  var poolInfo: VkCommandPoolCreateInfo
  poolInfo.sType = commandPoolCreateInfo
  poolInfo.queueFamilyIndex = queueFamilyIndices.graphicsFamily.uint32
  poolInfo.flags = 0 # Optional
  if vkCreateCommandPool(e.device, addr poolInfo, nil, addr e.commandPool) != success:
    raise newException(ValueError, "failed to create command pool")

proc createCommandBuffers(e: var Engine) =
  e.commandBuffers.setLen(e.swapChainFramebuffers.len)
  var allocInfo: VkCommandBufferAllocateInfo
  allocInfo.sType = commandBufferAllocateInfo
  allocInfo.commandPool = e.commandPool
  allocInfo.level = VkCommandBufferLevel.primary
  allocInfo.commandBufferCount = e.commandBuffers.len.uint32
  if vkAllocateCommandBuffers(e.device, addr allocInfo, addr e.commandBuffers[0]) != success:
    raise newException(ValueError, "failed to allocate command buffers")

  for i in 0 .. e.commandBuffers.high:
    var beginInfo: VkCommandBufferBeginInfo
    beginInfo.sType = commandBufferBeginInfo
    beginInfo.flags = 0 # Optional
    beginInfo.pInheritanceInfo = nil # Optional

    if vkBeginCommandBuffer(e.commandBuffers[i], addr beginInfo) != success:
      raise newException(ValueError, "failed to begin recording command buffer")

    var renderPassInfo: VkRenderPassBeginInfo
    renderPassInfo.sType = renderPassBeginInfo;
    renderPassInfo.renderPass = e.renderPass
    renderPassInfo.framebuffer = e.swapChainFramebuffers[i]

    # renderPassInfo.renderArea.offset = {0, 0};
    renderPassInfo.renderArea.extent = e.swapChainExtent

    var clearColor: VkClearValue
    clearColor.color.float32 = [0.cfloat, 0, 0, 1]
    renderPassInfo.clearValueCount = 1
    renderPassInfo.pClearValues = addr clearColor

    vkCmdBeginRenderPass(e.commandBuffers[i], addr renderPassInfo, VkSubpassContents.inline)
    vkCmdBindPipeline(e.commandBuffers[i], VkPipelineBindPoint.graphics, e.graphicsPipeline)
    vkCmdDraw(e.commandBuffers[i], 3, 1, 0, 0)
    vkCmdEndRenderPass(e.commandBuffers[i])

    if vkEndCommandBuffer(e.commandBuffers[i]) != success:
      raise newException(ValueError, "failed to record command buffer")

proc createSemaphores(e: var Engine) =
  var semaphoreInfo: VkSemaphoreCreateInfo
  semaphoreInfo.sType = semaphoreCreateInfo
  if vkCreateSemaphore(e.device, addr semaphoreInfo, nil, addr e.imageAvailableSemaphore) != success or
      vkCreateSemaphore(e.device, addr semaphoreInfo, nil, addr e.renderFinishedSemaphore) != success:
    raise newException(ValueError, "failed to create semaphores")

proc initVulkan(e: var Engine) =
  e.createInstance()
  e.setupDebugMessenger()
  e.createSurface()
  e.pickPhysicalDevice()
  e.createLogicalDevice()
  e.createSwapChain()
  e.createImageViews()
  e.createRenderPass()
  e.createGraphicsPipeline()
  e.createFramebuffers()
  e.createCommandPool()
  e.createCommandBuffers()
  e.createSemaphores()

  var extensionCount: uint32 = 0
  discard vkEnumerateInstanceExtensionProperties(nil, extensionCount.addr, nil)
  var extensionsArray = newSeq[VkExtensionProperties](extensionCount)
  discard vkEnumerateInstanceExtensionProperties(nil, extensionCount.addr, extensionsArray[0].addr)

  for extension in extensionsArray:
    echo extension.extensionName.toString()

proc run(e: var Engine) =
  e.initWindow()
  e.initVulkan()
  e.mainLoop()
  e.cleanup()

if isMainModule:
  var e: Engine
  e.run()
  # initWindow()
  # initVulkan()
  # loop()
  # cleanUp()

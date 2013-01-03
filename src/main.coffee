(->

  class WaveShade

    srcFragPrefix = 'precision highp float;'

    sampleRenderSrcVert = '''
      #define TAU 6.283185307179586
      attribute vec3 position;
      attribute vec2 texcoord;
      uniform float bufferSize, samplePosition, sampleRate;
      varying float time;

      void main() {
        float i = texcoord.x * bufferSize;
        time = (samplePosition + i) / sampleRate * TAU;
        gl_Position = vec4(position, 1.);
      }
      '''

    encodeSrcVert = '''
      attribute vec3 position;
      attribute vec2 texcoord;
      varying vec2 vTexcoord;

      void main() {
        vTexcoord = texcoord;
        gl_Position = vec4(position, 1.);
      }
      '''

    encodeSrcFrag = """
      #{srcFragPrefix}
      uniform sampler2D uTexture;
      varying vec2 vTexcoord;

      vec4 packFloatToVec4i(const float value) {
        const vec4 bitSh = vec4(256. * 256. * 256., 256. * 256., 256., 1.);
        const vec4 bitMsk = vec4(0., 1. / 256., 1. / 256., 1. / 256.);
        vec4 res = fract(value * bitSh);
        res -= res.xxyz * bitMsk;
        return res;
      }

      void main() {
        vec4 v = texture2D(uTexture, vTexcoord);
        gl_FragColor = packFloatToVec4i((v.x + 1.) * .5);
      }
      """

    viewRenderSrcVert = '''
      attribute vec3 position;
      attribute vec2 texcoord;
      varying vec2 vTexcoord;

      void main() {
        vTexcoord = texcoord;
        gl_Position = vec4(position, 1.);
      }
      '''

    viewRenderSrcFrag = """
      #{srcFragPrefix}
      uniform sampler2D uTexture;
      varying vec2 vTexcoord;

      void main() {
        float v = (texture2D(uTexture, vTexcoord).x + 1.) * .5;
        float c = float(v > vTexcoord.y);
        c *= vTexcoord.y / v;
        gl_FragColor = vec4(c, c, c, 1.);
      }
      """

    decodeFloat = (arr, i) ->
      (arr[i + 1] * (1 / (256 * 256 * 256)) +
       arr[i + 2] * (1 / (256 * 256)) +
       arr[i + 3] * (1 / 256)) * 2 - 1

    constructor: ->
      self = this

      @codeTextarea = document.getElementById('code-textarea')
      @codeMirror = CodeMirror.fromTextArea(@codeTextarea,
        mode: 'glsl'
        lineNumbers: true
      )
      @codeMirror.on('change', -> self.compile())

      # Setup Audio
      @audioContext = new webkitAudioContext()
      @audioNode = @audioContext.createJavaScriptNode(2048, 0, 2)
      @audioNode.onaudioprocess = (e) ->
        dataLeft  = e.outputBuffer.getChannelData(0)
        dataRight = e.outputBuffer.getChannelData(1)
        self.renderSampleBuffer(dataLeft, dataRight)

      bufferSize = @audioNode.bufferSize

      @encodedSampleBuffer = new Uint8Array(bufferSize * 4)

      # Setup GL
      @canvas = document.getElementById('gl-canvas')
      @canvas.width = @canvas.clientWidth
      @canvas.height = @canvas.clientHeight
      gl = @canvas.getContext('experimental-webgl')

      embr.setContext(gl)

      @glFloatExt = gl.getExtension('OES_texture_float')
      throw 'Float textures not supported :(' if not @glFloatExt

      @sampleRenderFbo = new embr.Fbo()
        .attach(new embr.Texture(
          width: bufferSize
          height: 1
          type: gl.FLOAT
          data: null
        ))
        .check()

      @encodeFbo = new embr.Fbo()
        .attach(new embr.Texture(
          width: bufferSize
          height: 1
          data: null
        ))
        .check()

      @encodeProg = new embr.Program(
        vertex: encodeSrcVert
        fragment: encodeSrcFrag
      ).link()

      @renderViewProg = new embr.Program(
        vertex: viewRenderSrcVert
        fragment: viewRenderSrcFrag
      ).link()

      @unitPlane = embr.Vbo.createPlane(-1, -1, 1, 1)

      @compile()

    compile: ->
      try
        tmpProg = new embr.Program(
          vertex: sampleRenderSrcVert
          fragment: srcFragPrefix + @codeMirror.getValue()
        )
      catch err
        console.error(err)

      if tmpProg?
        console.log('Compile Successful!')
        @sampleRenderProg?.cleanup()
        @sampleRenderProg = tmpProg
        @sampleRenderProg.link()

      return @

    renderSampleBuffer: (dataLeft, dataRight) ->
      bufferSize = @audioNode.bufferSize
      sampleRate = @audioContext.sampleRate

      gl = embr.gl
      gl.viewport(0, 0, bufferSize, 1)

      @sampleRenderFbo.bind()
      @unitPlane.setProgram(@sampleRenderProg.use(
        bufferSize: bufferSize
        samplePosition: @samplePosition
        sampleRate: sampleRate
      )).draw()
      @sampleRenderFbo.unbind()

      @encodeFbo.bind()
      @sampleRenderFbo.textures[0].bind()
      @unitPlane.setProgram(@encodeProg.use()).draw()
      @sampleRenderFbo.textures[0].unbind()
      gl.readPixels(0, 0, bufferSize, 1, gl.RGBA, gl.UNSIGNED_BYTE, @encodedSampleBuffer)
      @encodeFbo.unbind()

      gl.viewport(0, 0, @canvas.width, @canvas.height)
      gl.clearColor(0, 0, 0, 1)
      gl.clear(gl.COLOR_BUFFER_BIT)
      @sampleRenderFbo.textures[0].bind()
      @unitPlane.setProgram(@renderViewProg.use()).draw()
      @sampleRenderFbo.textures[0].unbind()

      for i in [0...bufferSize]
        decodedValue = decodeFloat(@encodedSampleBuffer, i * 4)
        dataLeft[i] = dataRight[i] = decodedValue

      @samplePosition += bufferSize

    startAudio: ->
      @samplePosition = 0
      @audioNode.connect(@audioContext.destination)
      return @
    stopAudio: ->
      @audioNode.disconnect()
      return @

  window.addEventListener 'DOMContentLoaded', ->
    window.wave = new WaveShade().startAudio()

).call(this)

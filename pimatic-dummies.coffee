module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = require 'cassert'

  t = env.require('decl-api').types
  _ = env.require('lodash')
  Color = require 'color'
  color_schema = require './color_schema.json'
  BaseLedLight = require('./base')(env)
  M = env.matcher


  class DummiesPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      deviceConfigDef = require('./device-config-schema.coffee')
      @framework.deviceManager.registerDeviceClass 'DummyLedLight',
        configDef: deviceConfigDef.DummyLedLight
        createCallback: (config) -> return new DummyLedLight(config)
      @framework.deviceManager.registerDeviceClass 'DummyLightRGBCT',
        configDef: deviceConfigDef.DummyLightRGBCT
        createCallback: (config) -> return new DummyLightRGBCT(config)

      @framework.ruleManager.addActionProvider(new ColorActionProvider(@framework))


      @framework.on "after init", =>
        # Check if the mobile-frontend was loaded and get a instance
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', 'pimatic-dummies/ui/dummies.coffee'
          mobileFrontend.registerAssetFile 'css', 'pimatic-dummies/ui/dummies.css'
          mobileFrontend.registerAssetFile 'html', 'pimatic-dummies/ui/dummies.jade'
          mobileFrontend.registerAssetFile 'js', 'pimatic-dummies/ui/vendor/spectrum.js'
          mobileFrontend.registerAssetFile 'css', 'pimatic-dummies/ui/vendor/spectrum.css'
          mobileFrontend.registerAssetFile 'js', 'pimatic-dummies/ui/vendor/async.js'
        else
          env.logger.warn 'your plugin could not find the mobile-frontend. No gui will be available'


  class DummyLedLight extends BaseLedLight

    constructor: (@config, lastState) ->
      @device = @
      @name = @config.name
      @id = @config.id
      @_dimlevel = lastState?.dimlevel?.value or 0

      initState = _.clone lastState
      for key, value of lastState
        initState[key] = value.value
      super(initState)
      if @power then @turnOn() else @turnOff()

    _updateState: (attr) ->
      state = _.assign @getState(), attr
      super null, state

    turnOn: ->
      @_updateState power: true
      Promise.resolve()

    turnOff: ->
      @_updateState power: false
      Promise.resolve()

    toggle: =>
      if @power is false then @turnOn() else @turnOff()
      Promise.resolve()    

    setColor: (newColor) ->
      color = Color(newColor).rgb()
      @_updateState
        mode: @COLOR_MODE
        color: color
      Promise.resolve()

    setWhite: ->
      @_updateState mode: @WHITE_MODE
      Promise.resolve()

    setBrightness: (newBrightness) ->
      @_updateState brightness: newBrightness
      Promise.resolve()

    getDimlevel: () ->
      Promise.resolve @_dimlevel

    changeDimlevelTo: (dimLevel) -> 
      @setBrightness(dimLevel)


    execute: (params) =>
      switch params.type
        when "color"
          return @setColor(params.value)
        when "temperature"
          temperatureColor = new Color()
          hue = 30 + 240 * (30 - params.value) / 60;
          temperatureColor.hsl(hue, 70, 50)

          hexColor = '#'
          hexColor += temperatureColor.rgb().r.toString(16)
          hexColor += temperatureColor.rgb().g.toString(16)
          hexColor += temperatureColor.rgb().b.toString(16)

          return @setColor(hexColor)
        else
          return Promise.reject("wrong parameter type " + params.type)

    destroy:()=>
      super()

  class DummyLightRGBCT extends env.devices.DimmerActuator

    _lastdimlevel: null
    template: 'light-rgbct'

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @_state = lastState?.state?.value or off
      @_dimlevel = lastState?.dimlevel?.value or 0
      @_lastdimlevel = lastState?.lastdimlevel?.value or 100
      @ctmin = 153
      @ctmax = 500
      @_ct = lastState?.ct?.value or @ctmin
      @_color = lastState?.color?.value or ''

      @addAttribute  'ct',
        description: "color Temperature",
        type: t.number
      @addAttribute  'color',
        description: 'color of the light'
        type: t.string



      @actions.setColor =
        description: 'set a light color'
        params:
          colorCode:
            type: t.string
      @actions.setCT =
        description: 'set light CT color'
        params:
          colorCode:
            type: t.number

      super()


    getTemplateName: -> "light-rgbct"

    getCt: -> Promise.resolve(@_ct)

    _setCt: (color) =>
      if @_ct is color then return
      @_ct = color
      @emit "ct", color


    setCT: (color,time) =>
      param = {
        on: true,
        ct: Math.round(@ctmin + color / 100 * (@ctmax-@ctmin)),
        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setCt(color)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    turnOn: ->
      @changeDimlevelTo(@_lastdimlevel)

    turnOff: ->
      @changeDimlevelTo(0)

    changeDimlevelTo: (level, time) ->
      param = {
        on: level != 0,
        transitiontime: time or @_transtime
      }
      if (level > 0)
        param.bri=Math.round(level*(2.54))
      @_sendState(param).then( () =>
        unless @_dimlevel is 0
          @_lastdimlevel = @_dimlevel
        @_setDimlevel(level)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    _setColor: (color) =>
      return new Promise((resolve,reject) =>
        #if @_color is color then return
        @_color = color
        @emit "color", color
        resolve()
      )

    getColor: -> Promise.resolve(@_color)

    setColor: (newColor) ->
      #color = new Color(newColor).rgb()
      return @_setColor(newColor)


    check = (val) ->
      val = Math.max(Math.min(val, 255), 0) / 255.0
      if val <= 0.04045
        return val / 12.92
      else
        return ((val + 0.055) / 1.055) ** 2.4

    rgb_to_xyY: (r, g, b) ->
      r = check(r)
      g = check(g)
      b = check(b)
      X = 0.76103282*r + 0.29537849*g + 0.04208869*b
      Y = 0.39240755*r + 0.59075697*g + 0.01683548*b
      Z = 0.03567341*r + 0.0984595*g + 0.22166709*b
      total = X + Y + Z
      if ( total == 0 )
        return  [ 0.44758179 , 0.4074481 ]
      else
        return [ X / total , Y / total]

    _sendState: (param) ->
      return Promise.resolve()

    execute: (params) =>
      env.logger.debug "Execute " + JSON.stringify(params,null,2)
      switch params.type
        when "color"
          if params.value.startsWith('#')
            _params = (params.value).substring(1)
          else
            _params = params.value
          return @setColor(params.value)
        when "temperature"
          return @setCT(params.value)
        else
          return Promise.reject("wrong parameter type " + params.type)

    destroy: ->
      super()


  class ColorActionProvider extends env.actions.ActionProvider
      constructor: (@framework) ->

      parseAction: (input, context) =>
        lightDevices = _(@framework.deviceManager.devices).values().filter(
          (device) => device.hasAction("setColor") or device.hasAction("setCT")
        ).value()

        hadPrefix = false

        # Try to match the input string with: set ->
        m = M(input, context).match(['set '])

        device = null
        color = null
        match = null
        variable = null

        # device name -> color
        m.matchDevice lightDevices, (m, d) ->
          # Already had a match with another device?
          if device? and device.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return

          device = d

          m.match [' to '], (m) ->
            m.or [
              # rgb hex like #00FF00
              (m) ->
                # TODO: forward pattern to UI
                m.match [/(#[a-fA-F\d]{6})(.*)/], (m, s) ->
                  color = s.trim()
                  match = m.getFullMatch()

              # color name like red
              (m) -> m.match _.keys(color_schema), (m, s) ->
                  color = color_schema[s]
                  match = m.getFullMatch()

              # color by temperature from variable like $weather.temperature = 30
              (m) ->
                m.match ['temperature based color by variable '], (m) ->
                  m.matchVariable (m, s) ->
                    variable = s
                    match = m.getFullMatch()
            ]

        if match?
          assert device?
          # either variable or color should be set
          assert variable? ^ color?
          assert typeof match is "string"
          return {
            token: match
            nextInput: input.substring(match.length)
            actionHandler: new ColorActionHandler(@, device, color, variable)
          }
        else
          return null

  class ColorActionHandler extends env.actions.ActionHandler
    constructor: (@framework, @device, @color, @variable) ->

    executeAction: (simulate) =>
      if simulate
        return Promise.resolve(__("would log set color #{@color}"))
      else
        @params = {}
        if @variable?
          @framwework.evaluateStringExpression([@variable])
          .then((temperature) =>
            @params =
              type: "temperature"
              value: temperature
          )
        else
          @params =
            type: "color"
            value: @color

        @device.execute(@params)
        .then(()=>
          return __("\"%s\" Rule executed", "set #{@params.type} to #{@params.value}")
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "set #{@params.type} to #{@params.value}")
        )

  return new DummiesPlugin()

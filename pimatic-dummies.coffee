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


    destroy:()=>
      super()

  class DummyLightRGBCT extends env.devices.DimmerActuator

    _lastdimlevel: null
    template: 'light-rgbct'

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @_dimlevel = lastState?.dimlevel?.value or 0
      @_lastdimlevel = lastState?.lastdimlevel?.value or 100
      @_state = lastState?.state?.value or off
      @_transtime = @config.transtime

      @addAttribute  'ct',
          description: "color Temperature",
          type: t.number
      @addAttribute  'hue',
          description: "color Temperature",
          type: t.number
      @addAttribute  'sat',
          description: "color Temperature",
          type: t.number

      @ctmin = 153
      @ctmax = 500
      @_ct = lastState?.ct?.value or @ctmin
      #@_color = 0
      @_hue = lastState?.hue?.value
      @_sat = lastState?.sat?.value

      @actions.setCT =
        description: 'set light CT color'
        params:
          colorCode:
            type: t.number
      @actions.changeHueSatTo =
        description: 'set light color'
        params:
          hue:
            type: t.number
          sat:
            type: t.number
          time:
            type: t.number
            optional: yes
      @actions.changeHueSatValTo =
        description: 'set light color values without transmit'
        params:
          hue:
            type: t.number
          sat:
            type: t.number
      @actions.setRGB =
        description: 'set light color'
        params:
          r:
            type: t.number
          g:
            type: t.number
          b:
            type: t.number
      @actions.changeHueTo =
        description: 'set light color'
        params:
          hue:
            type: t.number
          time:
            type: t.number
            optional: yes
      @actions.changeSatTo =
        description: 'set light color'
        params:
          sat:
            type: t.number
          time:
            type: t.number
            optional: yes

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

    _setHue: (hueVal) ->
      hueVal = parseFloat(hueVal)
      assert not isNaN(hueVal)
      assert 0 <= hueVal <= 100
      unless @_hue is hueVal
        @_hue = hueVal
        @emit "hue", hueVal

    _setSat: (satVal) ->
      satVal = parseFloat(satVal)
      assert not isNaN(satVal)
      assert 0 <= satVal <= 100
      unless @_sat is satVal
        @_sat = satVal
        @emit "sat", satVal

    getHue: -> Promise.resolve(@_hue)

    getSat: -> Promise.resolve(@_sat)

    changeHueTo: (hue, time) ->
      param = {
        on: true,
        hue: parseInt(hue/100*65535),
# not working with transtime
#        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setHue hue
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    changeSatTo: (sat, time) ->
      param = {
        on: true,
        sat: parseInt (sat/100*254),
# not working with transtime
#        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setSat sat
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )
    changeHueSatValTo: (hue, sat) ->
      @_setHue hue
      @_setSat sat
      return Promise.resolve()

    changeHueSatTo: (hue, sat, time) ->
      param = {
        on: true,
        sat: (sat/100*254),
        hue: (hue/100*65535),
        transitiontime: time or @_transtime
      }
      p1 = @changeSatTo(sat,time)
      p2 = @changeHueTo(hue,time)

      Promise.all([p1,p2]).then( () =>
        @_setHue hue
        @_setSat sat
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

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

    setRGB: (r,g,b,time) ->
      xy=@rgb_to_xyY(r,g,b)
      param = {
        on: true,
        xy: xy,
        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        #@_setCt(color)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    _sendState: (param) ->
      return Promise.resolve()
      ###
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.setLightState(@deviceID,param).then( (res) =>
          env.logger.debug ("New value send to device #{@name}")
          env.logger.debug (param)
          if res[0].success?
            return Promise.resolve()
          else
            if (res[0].error.type is 3 )
              @_setPresence(false)
              return Promise.reject(Error("device #{@name} not reachable"))
            else if (res[0].error.type is 201 )
              return Promise.reject(Error("device #{@name} is not modifiable. Device is set to off"))
            else Promise.reject(Error("general error"))
        ).catch( (error) =>
          return Promise.reject(error)
        )
      else
        env.logger.error ("gateway not online")
        return Promise.reject(Error("gateway not online"))
      ###

    destroy: ->
      super()


  class ColorActionProvider extends env.actions.ActionProvider
      constructor: (@framework) ->

      parseAction: (input, context) =>
        iwyDevices = _(@framework.deviceManager.devices).values().filter(
          (device) => device.hasAction("setColor")
        ).value()

        hadPrefix = false

        # Try to match the input string with: set ->
        m = M(input, context).match(['set '])

        device = null
        color = null
        match = null
        variable = null

        # device name -> color
        m.matchDevice iwyDevices, (m, d) ->
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
    constructor: (@provider, @device, @color, @variable) ->
      @_variableManager = null

      if @variable
        @_variableManager = @provider.framework.variableManager

    executeAction: (simulate) =>
      getColor = (callback) =>
        if @variable
          @_variableManager.evaluateStringExpression([@variable])
            .then (temperature) =>
              temperatureColor = new Color()
              hue = 30 + 240 * (30 - temperature) / 60;
              temperatureColor.hsl(hue, 70, 50)

              hexColor = '#'
              hexColor += temperatureColor.rgb().r.toString(16)
              hexColor += temperatureColor.rgb().g.toString(16)
              hexColor += temperatureColor.rgb().b.toString(16)

              callback hexColor, simulate
        else
          callback @color, simulate

      getColor @setColor

    setColor: (color, simulate) =>
      if simulate
        return Promise.resolve(__("would log set color #{color}"))
      else
        @device.setColor color
        return Promise.resolve(__("set color #{color}"))


  return new DummiesPlugin()

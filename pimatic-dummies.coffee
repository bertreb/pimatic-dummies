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

      @framework.ruleManager.addActionProvider(new ColorActionProvider(@framework))


      @framework.on "after init", =>
        # Check if the mobile-frontend was loaded and get a instance
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', 'pimatic-dummies/ui/led-light.coffee'
          mobileFrontend.registerAssetFile 'css', 'pimatic-dummies/ui/led-light.css'
          mobileFrontend.registerAssetFile 'html', 'pimatic-dummies/ui/led-light.html'
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

    destroy:()=>
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

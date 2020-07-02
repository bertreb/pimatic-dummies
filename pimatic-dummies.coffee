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

      oldClassName = "DummyLightRGBCT"
      newClassName = "DummyLightRGBW"
      for device,i in @framework.config.devices
        className = device.class
        #convert SoundsDevice to new ChromecastDevice
        if className == oldClassName
          @framework.config.devices[i].class = newClassName
          env.logger.debug "Class '#{oldClassName}' of device '#{device.id}' migrated to #{newClassName}"

      deviceConfigDef = require('./device-config-schema.coffee')
      @framework.deviceManager.registerDeviceClass 'DummyLedLight',
        configDef: deviceConfigDef.DummyLedLight
        createCallback: (config, lastState) -> return new DummyLedLight(config, lastState)
      @framework.deviceManager.registerDeviceClass 'DummyLightRGBW',
        configDef: deviceConfigDef.DummyLightRGBW
        createCallback: (config, lastState) => return new DummyLightRGBW(config, lastState, @framework)
      @framework.deviceManager.registerDeviceClass 'DummyThermostat',
        configDef: deviceConfigDef.DummyThermostat
        createCallback: (config, lastState) => return new DummyThermostat(config, lastState, @framework)

      @framework.ruleManager.addActionProvider(new ColorActionProvider(@framework))
      @framework.ruleManager.addActionProvider(new DummyThermostatActionProvider(@framework))


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

  class DummyLightRGBW extends env.devices.DimmerActuator

    _lastdimlevel: null
    template: 'light-rgbct'

    constructor: (@config,lastState, @framework) ->
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

      @framework.variableManager.waitForInit()
      .then(()=>
        @setColor(@_color)
      )

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


  class DummyThermostat extends env.devices.Device

    template: "dummythermostat"

    getTemplateName: -> "dummythermostat"

    actions:
      changePowerTo:
        params:
          power:
            type: "boolean"
      toggleEco:
        description: "Eco button toggle"
      changeModeTo:
        params:
          mode:
            type: "string"
      changeTemperatureTo:
        params:
          temperatureSetpoint:
            type: "number"
      changeTemperatureLowTo:
        params:
          temperatureSetpoint:
            type: "number"
      changeTemperatureHighTo:
        params:
          temperatureSetpoint:
            type: "number"
      changeProgramTo:
        params:
          program:
            type: "string"
      changeTemperatureRoomTo:
        params:
          temperature:
            type: "number"
      changeHumidityRoomTo:
        params:
          humidity:
            type: "number"
      changeTemperatureOutdoorTo:
        params:
          temperature:
            type: "number"
      changeHumidityOutdoorTo:
        params:
          humidity:
            type: "number"

    constructor: (@config, lastState, @framework) ->
      @id = @config.id
      @name = @config.name
      @_temperatureSetpoint = lastState?.temperatureSetpoint?.value or 20
      @_temperatureSetpointLow = lastState?.temperatureSetpointLow?.value or 18
      @_temperatureSetpointHigh = lastState?.temperatureSetpointHigh?.value or 22 # + @config.bufferRangeCelsius
      @_mode = lastState?.mode?.value or "heat"
      @_power = lastState?.power?.value or true
      @_eco = lastState?.eco?.value or false
      @_program = lastState?.program?.value or "manual"
      @_temperatureRoom = lastState?.temperatureRoom?.value or 20
      @_humidityRoom = lastState?.humidityRoom?.value or 50
      @_temperatureOutdoor = lastState?.temperatureOutdoor?.value or 20
      @_humidityOutdoor = lastState?.humidityOutdoor?.value or 50
      @_timeToTemperatureSetpoint = lastState?.timeToTemperatureSetpoint?.value or 0
      @_battery = lastState?.battery?.value or "ok"
      @_synced = true
      @_active = false
      @_heater = lastState?.heater?.value or false
      @_cooler = lastState?.cooler?.value or false
      @temperatureRoomSensor = false
      @humidityRoomSensor = false
      @temperatureOutdoorSensor = false
      @humidityOutdoorSensor = false
      @minThresholdCelsius = @config.minThresholdCelsius? or 5
      @maxThresholdCelsius = @config.maxThresholdCelsius? or 30


      @attributes =
        temperatureSetpoint:
          description: "The temp that should be set"
          type: "number"
          label: "Temperature Setpoint"
          unit: "°C"
          hidden: true
        temperatureSetpointLow:
          description: "The tempersture low that should be set in heatcool mode"
          type: "number"
          label: "Temperature SetpointLow"
          unit: "°C"
          hidden: true
        temperatureSetpointHigh:
          description: "The tempersture high that should be set in heatcool mode"
          type: "number"
          label: "Temperature SetpointHigh"
          unit: "°C"
          hidden: true
        power:
          description: "The power mode"
          type: "boolean"
          hidden: true
        eco:
          description: "The eco mode"
          type: "boolean"
          hidden: true
        mode:
          description: "The current mode"
          type: "string"
          enum: ["heat", "heatcool", "cool"]
          default: ["heat"]
          hidden: true
        program:
          description: "The program mode"
          type: "string"
          enum: ["manual", "auto"]
          default: ["manual"]
          hidden: true
        active:
          description: "If heating or cooling is active"
          type: "boolean"
          labels: ["active","ready"]
          acronym: "status"
        heater:
          description: "If heater is enabled"
          type: "boolean"
          labels: ["on","off"]
          acronym: "heater"
        cooler:
          description: "If cooler is enabled"
          type: "boolean"
          labels: ["on","off"]
          acronym: "cooler"
        timeToTemperatureSetpoint:
          description: "The time to reach the temperature setpoint"
          type: "number"
          unit: "sec"
          acronym: "time to setpoint"
        temperatureRoom:
          description: "The room temperature of the thermostat"
          type: "number"
          acronym: "T"
          unit: "°C"
        humidityRoom:
          description: "The room humidity of the thermostat"
          type: "number"
          acronym: "H"
          unit: "%"
          hidden: true
        temperatureOutdoor:
          description: "The outdoor temperature of the thermostat"
          type: "number"
          acronym: "TO"
          unit: "°C"
          hidden: true
        humidityOutdoor:
          description: "The outdoor humidity of the thermostat"
          type: "number"
          acronym: "HO"
          unit: "%"
          hidden: true
        battery:
          description: "Battery status"
          type: "string"
          #enum: ["ok", "low"]
          hidden: true
        synced:
          description: "Pimatic and thermostat in sync"
          type: "boolean"
          hidden: true

      @framework.variableManager.waitForInit()
      .then(()=>
        #the room sensors
        if @config.temperatureRoom?
          @_temperatureRoomDevice = @config.temperatureRoom.replace("$","").trim()
          @_temperatureRoomDevice = @_temperatureRoomDevice.split('.')
          if @_temperatureRoomDevice[0]?
            @temperatureRoomDevice = @framework.deviceManager.getDeviceById(@_temperatureRoomDevice[0])
            unless @temperatureRoomDevice?
              throw new Error "Unknown temperature device '#{@temperatureDevice}'"
            @temperatureRoomAttribute = @_temperatureRoomDevice[1]
            env.logger.info "@temperatureRoomAttribute " + JSON.stringify(@temperatureRoomAttribute,null,2)
            unless @temperatureRoomDevice.hasAttribute(@temperatureRoomAttribute)
              throw new Error "Unknown temperature room attribute '#{@temperatureRoomAttribute}'"
            env.logger.debug "Temperature room device found " + JSON.stringify(@temperatureRoomDevice.config,null,2)
            @attributes.temperatureRoom.hidden = false
            getter = 'get' + upperCaseFirst(@temperatureRoomAttribute)
            @temperatureRoomDevice[getter]()
            .then((temperatureRoom)=>
              env.logger.debug "Update temperture room " + temperatureRoom
              @changeTemperatureRoomTo(temperatureRoom)
            )
            @temperatureRoomDevice.system = @
            @temperatureRoomDevice.on @temperatureRoomAttribute, @temperatureRoomHandler
            @temperatureRoomSensor = true
        if @config.humidityRoom?
          @_humidityRoomDevice = @config.humidityRoom.replace("$","").trim()
          @_humidityRoomDevice = @_humidityRoomDevice.split('.')
          if @_humidityRoomDevice[0]?
            @humidityRoomDevice = @framework.deviceManager.getDeviceById(@_humidityRoomDevice[0])
            unless @humidityRoomDevice?
              throw new Error "Unknown humidity room device '#{@humidityRoomDevice}'"
            @humidityRoomAttribute = @_humidityRoomDevice[1]
            unless @humidityRoomDevice.hasAttribute(@humidityRoomAttribute)
              throw new Error "Unknown humidity attribute '#{@humidityRoomAttribute}'"
            env.logger.debug "Humidity room device found " + JSON.stringify(@humidityRoomDevice.config,null,2)
            @attributes.humidityRoom.hidden = false
            getter = 'get' + upperCaseFirst(@humidityRoomAttribute)
            @humidityRoomDevice[getter]()
            .then((humidityRoom)=>
              env.logger.debug "Update humidity room " + humidityRoom
              @changeHumidityRoomTo(humidityRoom)
            )
            @humidityRoomDevice.system = @
            @humidityRoomDevice.on @humidityRoomAttribute, @humidityRoomHandler
            @humidityRoomSensor = true

        # the outdoor sensors
        if @config.temperatureOutdoor?
          @_temperatureOutdoorDevice = @config.temperatureOutdoor.replace("$","").trim()
          @_temperatureOutdoorDevice = @_temperatureOutdoorDevice.split('.')
          if @_temperatureOutdoorDevice[0]?
            @temperatureOutdoorDevice = @framework.deviceManager.getDeviceById(@_temperatureOutdoorDevice[0])
            unless @temperatureOutdoorDevice?
              throw new Error "Unknown temperature Outdoor device '#{@temperatureOutdoorDevice}'"
            @temperatureOutdoorAttribute = @_temperatureOutdoorDevice[1]
            unless @temperatureOutdoorDevice.hasAttribute(@temperatureOutdoorAttribute)
              throw new Error "Unknown temperature attribute '#{@temperatureOutdoorAttribute}'"
            env.logger.debug "Temperature Outdoordevice found " + JSON.stringify(@temperatureOutdoorDevice.config,null,2)
            @attributes.temperatureOutdoor.hidden = false
            getter = 'get' + upperCaseFirst(@temperatureOutdoorAttribute)
            env.logger.debug "Getter temperatureOutdoorDevice " + getter
            @temperatureOutdoorDevice[getter]()
            .then((temperatureOutdoor)=>
              env.logger.debug "Update temperature outdoor " + temperatureOutdoor
              @changeTemperatureOutdoorTo(temperatureOutdoor)
            )
            @temperatureOutdoorDevice.system = @
            @temperatureOutdoorDevice.on @temperatureOutdoorAttribute, @temperatureOutdoorHandler
            @temperatureOutdoorSensor = true
        if @config.humidityOutdoor?
          @_humidityOutdoorDevice = @config.humidityOutdoor.replace("$","").trim()
          @_humidityOutdoorDevice = @_humidityOutdoorDevice.split('.')
          if @_humidityOutdoorDevice[0]?
            @humidityOutdoorDevice = @framework.deviceManager.getDeviceById(@_humidityOutdoorDevice[0])
            unless @humidityOutdoorDevice?
              throw new Error "Unknown humidity Outdoor device '#{@humidityOutdoorDevice}'"
            @humidityOutdoorAttribute = @_humidityOutdoorDevice[1]
            unless @humidityOutdoorDevice.hasAttribute(@humidityOutdoorAttribute)
              throw new Error "Unknown humidity Outdoor attribute '#{@humidityOutdoorAttribute}'"
            env.logger.debug "Humidity Outdoor device found " + JSON.stringify(@humidityOutdoorDevice.config,null,2)
            @attributes.humidityOutdoor.hidden = false
            getter = 'get' + upperCaseFirst(@humidityOutdoorAttribute)
            @humidityOutdoorDevice[getter]()
            .then((humidityOutdoor)=>
              env.logger.debug "Update humidity outdoor " + humidityOutdoor
              @changeHumidityOutdoorTo(humidityOutdoor)
            )
            @humidityOutdoorDevice.system = @
            @humidityOutdoorDevice.on @humidityOutdoorAttribute, @humidityOutdoorHandler
            @humidityOutdoorSensor = true
      )

      super()

    temperatureRoomHandler: (_temperatureRoom) =>
      temperatureRoom = Math.round(10*_temperatureRoom)/10
      @changeTemperatureRoomTo(temperatureRoom)

    humidityRoomHandler: (_humidityRoom) =>
      humidityRoom = Math.round(10*_humidityRoom)/10
      @changeHumidityRoomTo(humidityRoom)

    temperatureOutdoorHandler: (_temperatureOutdoor) =>
      temperatureOutdoor = Math.round(10*_temperatureOutdoor)/10
      @changeTemperatureOutdoorTo(temperatureOutdoor)

    humidityOutdoorHandler: (_humidityOutdoor) =>
      humidityOutdoor = Math.round(10*_humidityOutdoor)/10
      @changeHumidityOutdoorTo(humidityOutdoor)

    getMode: () -> Promise.resolve(@_mode)
    getPower: () -> Promise.resolve(@_power)
    getEco: () -> Promise.resolve(@_eco)
    getProgram: () -> Promise.resolve(@_program)
    getTemperatureSetpoint: () -> Promise.resolve(@_temperatureSetpoint)
    getTemperatureSetpointLow: () -> Promise.resolve(@_temperatureSetpointLow)
    getTemperatureSetpointHigh: () -> Promise.resolve(@_temperatureSetpointHigh)
    getActive: () -> Promise.resolve(@_active)
    getHeater: () -> Promise.resolve(@_heater)
    getCooler: () -> Promise.resolve(@_cooler)
    getTemperatureRoom: () -> Promise.resolve(@_temperatureRoom)
    getHumidityRoom: () -> Promise.resolve(@_humidityRoom)
    getTemperatureOutdoor: () -> Promise.resolve(@_temperatureOutdoor)
    getHumidityOutdoor: () -> Promise.resolve(@_humidityOutdoor)
    getTimeToTemperatureSetpoint: () -> Promise.resolve(@_timeToTemperatureSetpoint)
    getBattery: () -> Promise.resolve(@_battery)
    getSynced: () -> Promise.resolve(@_synced)

    upperCaseFirst = (string) ->
      unless string.length is 0
        string[0].toUpperCase() + string.slice(1)
      else ""

    _setMode: (mode) ->
      if mode is @_mode then return
      @_mode = mode
      @emit "mode", @_mode

    _setPower: (power) ->
      if power is @_power then return
      @_power = power
      @handleTemperatureChange()
      @emit "power", @_power

    _setEco: (eco) ->
      if eco is @_eco then return
      @_eco = eco
      @emit "eco", @_eco

    _setProgram: (program) ->
      if program is @_program then return
      @_program = program
      @emit "program", @_program

    _setSynced: (synced) ->
      if synced is @_synced then return
      @_synced = synced
      @emit "synced", @_synced

    _setSetpoint: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpoint then return
      @_temperatureSetpoint = temperatureSetpoint
      @emit "temperatureSetpoint", @_temperatureSetpoint

    _setSetpointLow: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpointLow then return
      @_temperatureSetpointLow = temperatureSetpoint
      @emit "temperatureSetpointLow", @_temperatureSetpointLow

    _setSetpointHigh: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpointHigh then return
      @_temperatureSetpointHigh = temperatureSetpoint
      @emit "temperatureSetpointHigh", @_temperatureSetpointHigh

    _setHeater: (heater) ->
      if heater is @_heater then return
      @_heater = heater
      @emit "heater", @_heater

    _setCooler: (cooler) ->
      if cooler is @_cooler then return
      @_cooler = cooler
      @emit "cooler", @_cooler

    _setBattery: (battery) ->
      if battery is @_battery then return
      @_battery = battery
      @emit "battery", @_battery

    _setActive: (active) ->
      if active is @_active then return
      @_active = active
      @emit "active", @_active

    _setTimeToTemperatureSetpoint: (time) ->
      if time is @_timeToTemperatureSetpoint then return
      @_timeToTemperatureSetpoint = time
      @emit "timeToTemperatureSetpoint", @_timeToTemperatureSetpoint

    _setTemperatureRoom: (temperatureRoom) ->
      if temperatureRoom is @_temperatureRoom then return
      @_temperatureRoom = temperatureRoom
      @emit "temperatureRoom", @_temperatureRoom

    _setHumidityRoom: (humidityRoom) ->
      if humidityRoom is @_humidityRoom then return
      @_humidityRoom = humidityRoom
      @emit "humidityRoom", @_humidityRoom

    _setTemperatureOutdoor: (temperatureOutdoor) ->
      if temperatureOutdoor is @_temperatureOutdoor then return
      @_temperatureOutdoor = temperatureOutdoor
      @emit "temperatureOutdoor", @_temperatureOutdoor

    _setHumidityOutdoor: (humidityOutdoor) ->
      if humidityOutdoor is @_humidityOutdoor then return
      @_humidityOutdoor = humidityOutdoor
      @emit "humidityOutdoor", @_humidityOutdoor

    changeModeTo: (mode) ->
      @_setMode(mode)
      @handleTemperatureChange()
      return Promise.resolve()

    changeProgramTo: (program) ->
      @_setProgram(program)
      return Promise.resolve()

    changePowerTo: (power) ->
      @_setPower(power)
      return Promise.resolve()

    toggleEco: () ->
      @_setEco(!@_eco)
      return Promise.resolve()

    changeEcoTo: (eco) ->
      @_setEco(eco)
      return Promise.resolve()

    changeActiveTo: (active) ->
      @_setActive(active)
      return Promise.resolve()

    changeHeaterTo: (heater) ->
      @_setHeater(heater)
      @_setActive(heater)
      return Promise.resolve()
    changeCoolerTo: (cooler) ->
      @_setCooler(cooler)
      @_setActive(cooler)
      return Promise.resolve()

    changeTimeToTemperatureSetpointTo: (time) ->
      @_setTimeToTemperatureSetpoint(time)
      return Promise.resolve()

    changeTemperatureRoomTo: (temperatureRoom) ->
      @_setTemperatureRoom(temperatureRoom)
      @handleTemperatureChange()
      return Promise.resolve()

    changeHumidityRoomTo: (humidityRoom) ->
      @_setHumidityRoom(humidityRoom)
      return Promise.resolve()

    changeTemperatureOutdoorTo: (temperatureOutdoor) ->
      @_setTemperatureOutdoor(temperatureOutdoor)
      @handleTemperatureChange()
      return Promise.resolve()

    changeHumidityOutdoorTo: (humidityOutdoor) ->
      @_setHumidityOutdoor(humidityOutdoor)
      return Promise.resolve()

    changeTemperatureTo: (_temperatureSetpoint) ->
      temperatureSetpoint = Math.round(10*_temperatureSetpoint)/10
      @_setSetpoint(temperatureSetpoint)
      @handleTemperatureChange()
      return Promise.resolve()

    changeTemperatureLowTo: (temperatureSetpoint) ->
      temperatureSetpoint = Math.round(10*_temperatureSetpoint)/10
      @_setSetpointLow(temperatureSetpoint)
      @handleTemperatureChange()
      return Promise.resolve()

    changeTemperatureHighTo: (temperatureSetpoint) ->
      temperatureSetpoint = Math.round(10*_temperatureSetpoint)/10
      @_setSetpointHigh(temperatureSetpoint)
      @handleTemperatureChange()
      return Promise.resolve()

    handleTemperatureChange: () =>
      # check if pid -> enable pid
      @getPower()
      .then((power)=>
        if power
          @getMode()
          .then((mode)=>
            switch mode
              when "heat"
                @changeCoolerTo(off)
                if @_temperatureSetpoint > @_temperatureRoom
                  @changeHeaterTo(on)
                else
                  @changeHeaterTo(off)
              when "cool"
                @changeHeaterTo(off)
                if @_temperatureSetpoint < @_temperatureRoom
                  @changeCoolerTo(on)
                else
                  @changeCoolerTo(off)
              when "heatcool"
                if @_temperatureSetpointLow > @_temperatureRoom
                  @changeHeaterTo(on)
                else
                  @changeHeaterTo(off)
                if @_temperatureSetpointHigh < @_temperatureRoom
                  @changeCoolerTo(on)
                else
                  @changeCoolerTo(off)
        )
        else
          @changeHeaterTo(off)
          @changeCoolerTo(off)
          @changeActiveTo(off)
      )

    execute: (device, command, options) =>
      env.logger.debug "Execute command: #{command} with options: " + JSON.stringify(options,null,2)
      return new Promise((resolve, reject) =>
        unless device?
          env.logger.info "Device '#{@name}' is unknown"
          return reject()
        switch command
          when "heat"
            @changeModeTo("heat")
          when "heatcool"
            @changeModeTo("heatcool")
          when "cool"
            @changeModeTo("cool")
          when "eco"
            @changeEcoTo(true)
          when "off"
            @changePowerTo(false)
          when "on"
            @changePowerTo(true)
          when "setpoint"
            @changeTemperatureTo(options.setpoint)
          when "setpointlow"
            @changeTemperatureLowTo(options.setpointHigh)
          when "setpointhigh"
            @changeTemperatureHighTo(options.setpointLow)
          when "manual"
            @changeProgramTo("manual")
          when "schedule"
            @changeProgramTo("schedule")
          else
            env.logger.debug "Unknown command received: " + command
            reject()
      )

    destroy: ->
      if @temperatureRoomDevice?
        @temperatureRoomDevice.removeListener(@temperatureRoomAttribute, @temperatureRoomHandler)
      if @humidityRoomDevice?
        @humidityRoomDevice.removeListener(@humidityRoomAttribute, @humidityRoomHandler)
      if @temperatureOutdoorDevice?
        @temperatureOutdoorDevice.removeListener(@temperatureOutdoorAttribute, @temperatureOutdoorHandler)
      if @humidityOutdoorDevice?
        @humidityOutdoorDevice.removeListener(@humidityOutdoorAttribute, @humidityOutdoorHandler)
      super()


  class DummyThermostatActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->

    parseAction: (input, context) =>

      @dummyThermostatDevice = null

      @command = ""

      @parameters = {}

      dummyThermostatDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class == "DummyThermostat"
      ).value()

      setCommand = (_command) =>
        @command = _command

      setpoint = (m,tokens) =>
        unless tokens >= @dummyThermostatDevice.config.minThresholdCelsius and tokens <= @dummyThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@dummyThermostatDevice.config.minThresholdCelsius} and #{@dummyThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpoint")
        @parameters["setpoint"] = Number tokens

      setpointlow = (m,tokens) =>
        unless tokens >= @dummyThermostatDevice.config.minThresholdCelsius and tokens <= @dummyThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@dummyThermostatDevice.config.minThresholdCelsius} and #{@dummyThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpointlow")
        @parameters["setpointLow"] = Number tokens

      setpointhigh = (m,tokens) =>
        unless tokens >= @dummyThermostatDevice.config.minThresholdCelsius and tokens <= @dummyThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@dummyThermostatDevice.config.minThresholdCelsius} and #{@dummyThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpointhigh")
        @parameters["setpointHigh"] = Number tokens

      m = M(input, context)
        .match('thermostat ')
        .matchDevice(dummyThermostatDevices, (m, d) =>
          # Already had a match with another device?
          if dummyThermostatDevice? and dummyThermostatDevice.config.id isnt d.config.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          @dummyThermostatDevice = d
        )
        .or([
          ((m) =>
            return m.match(' heat', (m)=>
              setCommand('heat')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' heatcool', (m)=>
              setCommand('heatcool')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' cool', (m)=>
              setCommand('cool')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' eco', (m)=>
              setCommand('eco')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' off', (m)=>
              setCommand('off')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' on', (m)=>
              setCommand('on')
              match = m.getFullMatch()
            )
          )
          ((m) =>
            return m.match(' setpoint ')
              .matchNumber(setpoint)
          ),
          ((m) =>
            return m.match(' setpoint low ')
              .matchNumber(setpointlow)
          ),
          ((m) =>
            return m.match(' setpoint high ')
              .matchNumber(setpointhigh)
          ),
          ((m) =>
            return m.match(' program ')
              .or([
                ((m) =>
                  return m.match(' manual', (m)=>
                    setCommand('manual')
                    match = m.getFullMatch()
                  )
                ),
                ((m) =>
                  return m.match(' schedule', (m)=>
                    setCommand('schedule')
                    match = m.getFullMatch()
                  )
                )
              ])
          )
        ])

      match = m.getFullMatch()
      if match?
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new DummyThermostatActionHandler(@framework, @dummyThermostatDevice, @command, @parameters)
        }
      else
        return null

  class DummyThermostatActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @dummyThermostatDevice, @command, @parameters) ->

    executeAction: (simulate) =>
      if simulate
        return __("would have cleaned \"%s\"", "")
      else
        @dummyThermostatDevice.execute(@dummyThermostatDevice, @command, @parameters)
        .then(()=>
          return __("\"%s\" Rule executed", @command)
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "")
        )



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
        variable = null
        match = null

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

              # color temperature number
              (m) -> m.matchNumber  (m, s) ->
                  lKT = 0
                  hKT = 100
                  if s < lKT or s > hKT
                    context?.addError("Color temprature must be between #{lKT} and #{hKT}")                 
                  color = s
                  match = m.getFullMatch()

              # color by from variable with hex color, color name or color temperature
              (m) ->
                m.matchVariable (m, s) ->
                  variable = s
                  match = m.getFullMatch()
            ]

        if match?
          assert device?
          # either variable or color should be set
          assert variable? ^ color?
          #assert typeof match is "string"
          return {
            token: match
            nextInput: input.substring(match.length)
            actionHandler: new ColorActionHandler(@framework, device, color, variable)
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
          varColor = @framework.variableManager.getVariableValue(@variable.replace("$",""))
          if varColor?
            @_color = varColor
        else
          @_color = @color
        if String(@_color).startsWith('#')
          @params =
            type: "color"
            value: @_color
        else
          @params =
            type: "temperature"
            value: @_color

        @device.execute(@params)
        .then(()=>
          return __("\"%s\" Rule executed", "set #{@params.type} to #{@params.value}")
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "set #{@params.type} to #{@params.value}")
        )

  return new DummiesPlugin()

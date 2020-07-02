# pimatic-dummies
Pimatic plugin for extra dummy devices

This plugin creates dummy devices to use within Pimatic. Dummy device are mostly used for user interaction via the gui and rule based actions. Dummy devices do not directly control a device.

The plugin supports 3 devices; DummyLedLight, DummyLightRGBW and DummyThermostat

DummyLedLight
----
The DummyLedLight device is a renewed pimatic-led-light device made useable with node 8+. Its a dimmer actuator device with brightness (the dimmer), color temperature and color (RGB).

![](/screens/dummy-led.png)

The device can be controlled via the gui and via rules.

The rules syntax:

`
set <DummyLedLight device> to [<hex color> | <colorname> | <temperature> | <$variable>]
`

DummyLightRGBW
----
The DummyLightRGBW device is a dimmer actuator device with brightness (the dimmer), color temprature and color (RGB).
This device is based on the RaspBee-RGBCT device from [treban](https://github.com/treban/pimatic-raspbee)

![](/screens/dummy-rgbw.png)

The device can be controlled via the gui and via rules.

The rules syntax:

`
set <DummyLightRGBW device> to [<hex color> | <colorname> | <temperature> | <$variable>]
`

#### Color definitions

`
<hex color> is in the format #[0-F][0-F][0-F][0-F][0-F][0-F] // like #1F00A0
`

\<color names> can be found in color_schema.json

\<temperature> must be between 0-100

For the content of the variable, the same color logic applies

DummyThermostat
----
The DummyThermostat device is a thermostat device with a heat, heatcool and cool mode.

![](/screens/dummy-thermostat.png)

The device can be controlled via the gui and via rules.

The rules syntax:

`
thermostat <DummyThermostat device>
    heat | heatcool | cool |
    on | eco | off |
    setpoint [<temperature>|<$temp variable>] |
    setpoint low [<temperature>|<$temp variable>] | setpoint high [<temperature>|<$temp variable] |
    program manual | program auto
`
With this device you get the maximum thermostat functionality in Google Assistant. For that this device can be added in pimatic-assistant.
Real heaters and coolers can be connected via rules based on the DummyThermostat variables. 

The variables to be set:
`
- setPoint: The target temperature in heat or cool mode. The first input in gui.
- setPointLow: The Low target temperature in heatcool mode. Below that value the heater will turn on. The second input in the gui.
- setPointHigh: The High target temperature in heatcool mode. Above that value the cooler with turn on. The third input in the gui
- eco: Set the whole thermostat in eco state
- power: Switch the thermostat on or off
- mode: The current mode of the heater (heat,heatcool or cool)
- program: The current program  (manual or auto)
`

The state variables:
`
- active: True if heater or cooler is on
- heater: True if the heater is on
- cooler: True if the cooler is on
`

# Template.gritsSearch
#
# When another meteor app adds grits:grits-net-meteor as a package
# Template.gritsSearch will be available globally.
_init = true # flag, set to false when initialization is done
_initStartDate = null # onCreated will initialize the date through GritsFilterCriteria
_initEndDate = null # onCreated will initialize the date through GritsFilterCriteria
_departureSearchMain = null # onRendered will set this to a typeahead object
_effectiveDatePicker = null # onRendered will set this to a datetime picker object
_discontinuedDatePicker = null # onRendered will set this to a datetime picker object
_matchSkip = null # the amount to skip during typeahead pagination
_simulationProgress = new ReactiveVar(0)

# Unfortunately we need to result to jQuery as twitter's typeahead plugin does
# not allow us to pass in a custom context to the footer.  <%= obj.query %> and
# <%= obj.isEmpty %> are the only things available.
_typeaheadFooter = _.template '
  <div class="tt-footer airport-footer">
    <span id="suggestionCount"></span>
    <ul class="pager">
      <li class="previous-suggestions">
        <a href="#" id="previousSuggestions" class="btn btn-default">Previous</a>
      </li>
      <li class="next-suggestions">
        <a href="#" id="forwardSuggestions" class="btn btn-default">Next</a>
      </li>
    </ul>
  </div>'

# returns the typeahead object for the '#departureSearchMain' input
#
# @see: http://sliptree.github.io/bootstrap-tokenfield/#methods
# @return [Object] typeahead
getDepartureSearchMain = ->
  _departureSearchMain

# sets the typeahead object for the '#departureSearchMain' input
_setDepartureSearchMain = (typeahead) ->
  _departureSearchMain = typeahead

# returns the datetime picker object for the '#effectiveDate' input  with the label 'End'
#
# @see http://eonasdan.github.io/bootstrap-datetimepicker/Functions/
# @return [Object] datetimePicker object
getEffectiveDatePicker = ->
  _effectiveDatePicker

# sets the datetime picker object for the '#effectiveDate' input with the label 'End'
_setEffectiveDatePicker = (datetimePicker) ->
  _effectiveDatePicker = datetimePicker

# returns the datetime picker object for the '#discontinuedDate' input with the label 'Start'
#
# @see http://eonasdan.github.io/bootstrap-datetimepicker/Functions/
# @return [Object] datetimePicker object
getDiscontinuedDatePicker = ->
  _discontinuedDatePicker

# sets the datetime picker object for the '#discontinuedDate' input with the label 'Start'
_setDiscontinuedDatePicker = (datetimePicker) ->
  _discontinuedDatePicker = datetimePicker

# determines which field was matched by the typeahead into the server response
#
# @param [String] input, the string used as the search
# @param [Array] results, the server response
# @return [Array] array of matches, with all properties of the model to be available in the suggestion template under the key 'raw'.
_determineFieldMatchesByWeight = (input, res) ->
  numComparator = (a, b) ->
    a - b
  strComparator = (a, b) ->
    if a < b
      return -1
    if a > b
      return 1
    return 0
  compare = (a, b) ->
    return strComparator(a.label, b.label) || numComparator(a.weight, b.weight)

  matches = []
  for obj in res
    if obj.propertyMatch
      propertyLabel = switch obj.propertyMatch
        when "countryName" then "Country Name"
        when "stateName" then "State Name"
        when "city" then "City Name"
        else
          obj.propertyMatch
      matches.push
        label: "#{obj.propertyMatch}:" + obj._id
        value: "#{propertyLabel}: " + obj._id
        field: obj.propertyMatch
        propertyMatch:
          "#{obj.propertyMatch}": true
        weight: 100
        display: obj._id
        raw: obj
      continue
    # get the typeahead matcher from the Astro Class, contains weight, display
    # and regexOptions
    typeaheadMatcher = Airport.typeaheadMatcher()
    for field, matcher of typeaheadMatcher
      regex = new RegExp(matcher.regexSearch({search: input}), matcher.regexOptions)
      value = obj[field]
      # cannot match on an empty value
      if _.isEmpty(value)
        continue
      # apply the regex to the value
      if value.match(regex) != null
        # determine if its a previous match
        match = _.find(matches, (m) -> m.label == obj._id)
        # if not, create a new object and assign the properties
        # note: prefix is added to avoid possible confict with the class fields
        # that are extended.
        if _.isUndefined(match)
          match =
            label: obj._id
            value: value
            field: field
            weight: matcher.weight
            display: matcher.display
            raw: obj
          matches.push(match)
          continue
        else
          # Previous match exists, update the values if its of heigher weight
          if matcher.weight > match.weight
            match.value = value
            match.field = field
            match.weight = matcher.weight
            match.display = matcher.display
  if Meteor.gritsUtil.debug
    console.log('matches:', matches)
  matches

# method to generate suggestions and drive the pagination feature
_suggestionGenerator = (query, skip, callback) ->
  _matchSkip = skip
  Meteor.call 'typeaheadAirport', query, skip, (err, {results, count}) ->
    res = results
    if res.length > 0
      matches = _determineFieldMatchesByWeight(query, res)
      # expects an array of objects with keys [label, value]
      callback(matches)

    # keep going to update the _typeaheadFooter via jQuery
    # update the record count
    if count > 1
      if (_matchSkip + 10) > count
        diff = (_matchSkip + 10) - count
        $('#suggestionCount').html("<span>#{_matchSkip+1}-#{_matchSkip+(10-diff)} of #{count}</span>")
      else
        $('#suggestionCount').html("<span>#{_matchSkip+1}-#{_matchSkip+10} of #{count}</span>")
    else if count == 1
      $('#suggestionCount').html("<span>#{count} match found</span>")
    else
      $('.tt-suggestions').empty()
      $('#suggestionCount').html("<span>No matches found</span>")

    # enable/disable the pager elements
    if count <= 10
      $('.next-suggestions').addClass('disabled')
      $('.previous-suggestions').addClass('disabled')
    if count > 10
      # edge case min
      if _matchSkip == 0
        $('.previous-suggestions').addClass('disabled')
      # edge case max
      if (count - _matchSkip) <= 10
        $('.next-suggestions').addClass('disabled')

    # bind click handlers
    if !$('.previous-suggestions').hasClass('disabled')
      $('#previousSuggestions').bind 'click', (e) ->
        e.preventDefault()
        e.stopPropagation()
        if count <= 10 || _matchSkip <= 10
          _matchSkip = 0
        else
          _matchSkip -= 10
        _suggestionGenerator(query, _matchSkip, callback)

    if !$('.next-suggestions').hasClass('disabled')
      $('#forwardSuggestions').bind 'click', (e) ->
        e.preventDefault()
        e.stopPropagation()
        if count <= 10
          _matchSkip 0
        else
          _matchSkip += 10
        _suggestionGenerator(query, _matchSkip, callback)

# resets the simulation-progress bars
_resetSimulationProgress = ->
  _simulationProgress.set(0)
  $('.simulation-progress').css
    width: '0%'

# sets an object to be used by Meteors' Blaze templating engine (views)
Template.gritsSearch.helpers
  isSimulatorRunning: ->
    GritsFilterCriteria.isSimulatorRunning.get()

  isExploreMode: ->
    mode = Session.get(GritsConstants.SESSION_KEY_MODE)
    if _.isUndefined(mode)
      return false
    else
      if mode == GritsConstants.MODE_EXPLORE
        return true
      else
        return false

  isAnalyzeMode: ->
    mode = Session.get(GritsConstants.SESSION_KEY_MODE)
    if _.isUndefined(mode)
      return false
    else
      if mode == GritsConstants.MODE_ANALYZE
        return true
      else
        return false

  loadedRecords: ->
    Session.get(GritsConstants.SESSION_KEY_LOADED_RECORDS)

  totalRecords: ->
    Session.get(GritsConstants.SESSION_KEY_TOTAL_RECORDS)

  state: ->
    # GritsFilterCriteria.stateChanged is a reactive-var
    state = GritsFilterCriteria.stateChanged.get()
    if _.isNull(state)
      return
    if state
      true
    else
      false

  start: ->
    _initStartDate

  end: ->
    _initEndDate

  showNotify: ->
    Template.instance().notify.get()

  notBSVE: ->
    return !window.location.href.match(/bsve/i)

Template.gritsSearch.onCreated ->
  @notify = new ReactiveVar(false)
  _initStartDate = GritsFilterCriteria.initStart()
  _initEndDate = GritsFilterCriteria.initEnd()
  _init = false # done initializing initial input values

  # Public API
  # Currently we declare methods above for documentation purposes then assign
  # to the Template.gritsSearch as a global export
  Template.gritsSearch.getDepartureSearchMain = getDepartureSearchMain
  Template.gritsSearch.getEffectiveDatePicker = getEffectiveDatePicker
  Template.gritsSearch.getDiscontinuedDatePicker = getDiscontinuedDatePicker
  Template.gritsSearch.simulationProgress = _simulationProgress

# triggered when the 'filter' template is rendered
Template.gritsSearch.onRendered ->
  departureSearchMain = $('#departureSearchMain').tokenfield
    typeahead: [{hint: false, highlight: true},
      display: (match) ->
        if _.isUndefined(match)
          return
        return match.label
      templates:
        suggestion: (x)-> Blaze.toHTMLWithData(Template.suggestionTemplate, x)
        footer: _typeaheadFooter
      source: (query, callback) ->
        _suggestionGenerator(query, 0, callback)
        return
    ]
  _setDepartureSearchMain(departureSearchMain)

  # Toast notification options
  toastr.options =
    positionClass: 'toast-bottom-center'
    preventDuplicates: true,

  # set the effectiveDatePicker and options
  # Note: Meteor.gritsUtil.effectiveDateMinMax is set in startup.coffee
  options =
    format: 'MM/DD/YY'
    minDate: Meteor.gritsUtil.effectiveDateMinMax[0]
    maxDate: Meteor.gritsUtil.effectiveDateMinMax[1]
    widgetPositioning:
      vertical: 'top'

  effectiveDatePicker = $('#effectiveDate').datetimepicker(options)
  _setEffectiveDatePicker(effectiveDatePicker)


  # set the discontinuedDatePicker and options
  # Note: Meteor.gritsUtil.discontinuedDateMinMax is set in startup.coffee
  options =
    format: 'MM/DD/YY'
    minDate: Meteor.gritsUtil.discontinuedDateMinMax[0]
    maxDate: Meteor.gritsUtil.discontinuedDateMinMax[1]
    widgetPositioning:
      vertical: 'top'

  discontinuedDatePicker = $('#discontinuedDate').datetimepicker(options)
  _setDiscontinuedDatePicker(discontinuedDatePicker)

  # set the original state of the filter on document ready
  GritsFilterCriteria.setState()

  Meteor.setTimeout =>
    @$('.tt-input').focus()
  , 500

  # When the template is rendered, setup a Tracker autorun to listen to changes
  # on isUpdating.  This session reactive var enables/disables, shows/hides the
  # apply button and filterLoading indicator.
  @autorun ->
    # update the disabled status of the [More] button based loadedRecords
    loadedRecords = Session.get(GritsConstants.SESSION_KEY_LOADED_RECORDS)
    totalRecords = Session.get(GritsConstants.SESSION_KEY_TOTAL_RECORDS)
    if loadedRecords < totalRecords
      # enable the [More] button when loaded is less than total
      $('#loadMore').prop('disabled', false)
    else
      # disable the [More] button
      $('#loadMore').prop('disabled', true)

  @autorun ->
    # update the ajax-loader
    isUpdating = Session.get(GritsConstants.SESSION_KEY_IS_UPDATING)
    # do not show the filter spinner if the overlay isLoading
    if isUpdating and not Session.get 'loading'
      $('#applyFilter').prop('disabled', true)
      Session.set 'filtering', true
    else
      $('#applyFilter').prop('disabled', false)
      Session.set 'filtering', false

  @autorun ->
    mode = Session.get(GritsConstants.SESSION_KEY_MODE)
    # do not run if our mode hasn't changed
    if self.mode == mode
      return
    if mode == GritsConstants.MODE_EXPLORE
      _resetSimulationProgress()
      # reset the URL back to the root
      FlowRouter.go('/')
    else
      # initialize the bootstrap slider (this is not rendered by default in grits_search.html)
      # it is done using nextTick to give Blaze template time to render
      async.nextTick(-> $('#simulatedPassengersInputSlider').slider())
    self.mode = mode

  @autorun (c) ->
    departures = GritsFilterCriteria.departures.get()
    if departures.length == 0
      _resetSimulationProgress()
      if !c.firstRun
        # reset the route when the departures are cleared
        FlowRouter.go('/')

  # Determine if the router set a simId
  # @see lib/router.coffee
  @autorun (c) ->
    simId = Session.get(GritsConstants.SESSION_KEY_SHARED_SIMID)
    if _.isUndefined(simId)
      return
    # mark the simulator as running
    GritsFilterCriteria.isSimulatorRunning.set(true)
    Meteor.call 'findSimulationBySimId', simId, (err, simulation) ->
      if err
        Meteor.gritsUtil.errorHandler(err)
        console.error(err)
        return
      if _.isEmpty(simulation)
        Meteor.gritsUtil.errorHandler({message: 'Invalid simulation'})
        return
      # get the values from the simulation
      startDate = moment.utc(simulation.get('startDate'))
      endDate = moment.utc(simulation.get('endDate'))
      tokens = simulation.get('departureNodes')
      simPas = simulation.get('numberPassengers')
      # update the filter and UI elements
      GritsFilterCriteria.setOperatingDateRangeStart(startDate)
      GritsFilterCriteria.setOperatingDateRangeEnd(endDate)
      GritsFilterCriteria.setDepartures(tokens)
      # GritsFilterCriteria does not have a interface for the simulatedPassengersInputSlider
      async.nextTick ->
        $('#simulatedPassengersInputSlider').slider('setValue', simPas)
        $('#simulatedPassengersInputSliderValIndicator').html(simPas)
      # Update the dataTable
      Template.gritsDataTable.simId.set(simId)
      # Set the total records
      Session.set(GritsConstants.SESSION_KEY_TOTAL_RECORDS, simPas)
      # Process the existing simulation
      GritsFilterCriteria.processSimulation(simPas, simulation.get('simId'))

_changeSimulatedPassengersHandler = (e) ->
  val = parseInt($("#simulatedPassengersInputSlider").val(), 10)
  if val isnt _wfStartVal
    _wfStartVal = val
    if _.isNaN(val)
      val = null
    $('#simulatedPassengersInputSliderValIndicator').empty().html(val)

_changeDepartureHandler = (e) ->
  combined = []
  tokens =  _departureSearchMain.tokenfield('getTokens')
  codes = _.pluck(tokens, 'label')
  combined = _.union(codes, combined)
  if _.isEqual(combined, GritsFilterCriteria.departures.get())
    # do nothing
    return
  GritsFilterCriteria.departures.set(combined)

_changeDateHandler = (e) ->
  $target = $(e.target)
  id = $target.attr('id')
  if id == 'discontinuedDate'
    if _.isNull(_discontinuedDatePicker)
      return
    date = _discontinuedDatePicker.data('DateTimePicker').date()
    GritsFilterCriteria.operatingDateRangeStart.set(date)
    return
  if id == 'effectiveDate'
    if _.isNull(_effectiveDatePicker)
      return
    date = _effectiveDatePicker.data('DateTimePicker').date()
    GritsFilterCriteria.operatingDateRangeEnd.set(date)

_startSimulation = (e) ->
  simPas = parseInt($('#simulatedPassengersInputSlider').slider('getValue'), 10)
  startDate = _discontinuedDatePicker.data('DateTimePicker').date().format('DD/MM/YYYY')
  endDate = _effectiveDatePicker.data('DateTimePicker').date().format('DD/MM/YYYY')
  email = if $('#notify').prop('checked') then $('#notifyEmail').val() else null
  if email
    localStorage?.setItem('notifyEmail', email)
  GritsFilterCriteria.startSimulation(simPas, startDate, endDate, email)

_showThroughput = (e) ->
  departures = GritsFilterCriteria.departures.get()
  if departures.length == 0
    toastr.error(i18n.get('toastMessages.departureRequired'))
    return
  GritsFilterCriteria.apply()

# events
#
# Event handlers for the grits_filter.html template
Template.gritsSearch.events
  'keyup #departureSearchMain-tokenfield': (event) ->
    if event.keyCode == 13
      departures = GritsFilterCriteria.departures.get()
      if departures.length == 0
        toastr.error(i18n.get('toastMessages.departureRequired'))
        return
      GritsFilterCriteria.apply()

  'slideStop #simulatedPassengersInputSlider': _changeSimulatedPassengersHandler

  'click #startSimulation': _startSimulation

  'click #showThroughput': _showThroughput

  'click #notify': (event, template) ->
    Template.instance().notify.set(event.target.checked)
    Meteor.defer ->
      $('#notifyEmail').focus().val(localStorage?.notifyEmail or '')

  'change #departureSearchMain': _changeDepartureHandler

  'dp.change': _changeDateHandler

  'dp.show': (event) ->
    $datetimepicker = $(event.target)
    offset = $datetimepicker.offset()
    bottomPosition = window.innerHeight - offset.top
    $('.bootstrap-datetimepicker-widget.dropdown-menu').css
      bottom: bottomPosition + 5 # Add height of arrow
      top: 'auto'
      left: offset.left

  'click #includeNearbyAirports': (event) ->
    miles = parseInt($("#includeNearbyAirportsRadius").val(), 10)
    departures = GritsFilterCriteria.departures.get()

    if departures.length <= 0
      toastr.error(i18n.get('toastMessages.includeNearbyRequired'))
      false

    if (departures[0].indexOf(GritsMetaNode.PREFIX) >= 0)
      toastr.error(i18n.get('toastMessages.includeNearbyMetaNode'))
      false

    if $('#includeNearbyAirports').is(':checked')
      Session.set(GritsConstants.SESSION_KEY_IS_UPDATING, true)
      Meteor.call 'findNearbyAirports', departures[0], miles, (err, airports) ->
        if err
          Meteor.gritsUtil.errorHandler(err)
          return

        nearbyTokens = _.pluck(airports, '_id')
        union = _.union(departures, nearbyTokens)
        _departureSearchMain.tokenfield('setTokens', union)
        Session.set(GritsConstants.SESSION_KEY_IS_UPDATING, false)
    else
      departureSearch = getDepartureSearchMain()
      departureSearch.tokenfield('setTokens', departures)

  'click #toggleFilter': (e) ->
    $self = $(e.currentTarget)
    $("#filter").toggle("fast")

  'click #applyFilter': (event, template) ->
    GritsFilterCriteria.apply()

  'click #loadMore': ->
    GritsFilterCriteria.setOffset()
    mode = Session.get(GritsConstants.SESSION_KEY_MODE)
    if mode == GritsConstants.MODE_EXPLORE
      GritsFilterCriteria.more()

  'tokenfield:initialize': (e) ->
    $target = $(e.target)
    $container = $target.closest('.tokenized')
    #the typeahead menu should be as wide as the filter at a minimum
    id = $target.attr('id')
    $container.find('.tt-dropdown-menu').css
      bottom: 0
      top: $container.offset().top + $container.outerHeight() + 1
    $container.find('.tokenized.main').prepend($("#searchIcon"))
    $('#' + id + '-tokenfield').on 'blur', (e) ->
      # only allow tokens
      $container.find('.token-input.tt-input').val("")

  'tokenfield:createtoken': (e) ->
    $target = $(e.target)
    $container = $target.closest('.tokenized')
    tokens = $target.tokenfield('getTokens')
    match = _.find(tokens, (t) -> t.label == e.attrs.label)
    if match
      # do not create a token and clear the input
      $target.closest('.tokenized').find('.token-input.tt-input').val("")
      e.preventDefault()

  'tokenfield:createdtoken': (e) ->
    $target = $(e.target)
    tokens = $target.tokenfield('getTokens')
    token = e.attrs.label
    false

  'tokenfield:removedtoken': (e) ->
    $target = $(e.target)
    tokens = $target.tokenfield('getTokens')
    # determine if the remaining tokens is empty, then show the placeholder text
    if tokens.length == 0
      if $target.attr('id') in ['departureSearchMain']
        $('#includeNearbyAirports').prop('checked', false)
    token = e.attrs.label
    false

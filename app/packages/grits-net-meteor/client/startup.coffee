Meteor.startup ->
  # NOTE: *the gritsOverlay indicator will be showing by default*

  # initialize Session variables
  Session.set(GritsConstants.SESSION_KEY_IS_UPDATING, false)
  Session.set(GritsConstants.SESSION_KEY_LOADED_RECORDS, 0)
  Session.set(GritsConstants.SESSION_KEY_TOTAL_RECORDS, 0)
  Session.set(GritsConstants.SESSION_KEY_IS_READY, false) # the map will not be displayed until isReady is set to true
  Session.set 'loading', true

  # async flow control so we can set grits-net-meteor:isReady true when done
  if Meteor.gritsUtil.debug
    start = new Date()
    console.log('start sync [i18n, airports, effectiveDateMinMax, discontinuedDateMinMax]')
  async.auto(
    'i18n': (callback, result) ->
      # string externalization/i18n
      Template.registerHelper('_', i18n.get)
      i18n.loadAll(() ->
        i18n.setLanguage('en')
        if Meteor.gritsUtil.debug
          console.log('done i18n')
        callback(null, true)
      )
    'airports': (callback, result) ->
      Meteor.call('findActiveAirports', (err, airports) ->
        if err
          callback(err)
          return
        Meteor.gritsUtil.airports = airports
        Meteor.gritsUtil.airportsToLocations = _.object([
          airport['_id']
          airport['loc']['coordinates']
        ] for airport in airports)

        if Meteor.gritsUtil.debug
          console.log('done airports')
        callback(null, true)
      )
    'effectiveDate': (callback, result) ->
      Meteor.call('findMinMaxDateRange', 'effectiveDate', (err, minMax) ->
        if err
          callback(err)
          return
        Meteor.gritsUtil.effectiveDateMinMax = minMax
        if Meteor.gritsUtil.debug
          console.log('done effectiveDate')
        callback(null, true)
      )
    'discontinuedDate': (callback, result) ->
      Meteor.call('findMinMaxDateRange', 'discontinuedDate', (err, minMax) ->
        if err
          callback(err)
          return
        Meteor.gritsUtil.discontinuedDateMinMax = minMax
        if Meteor.gritsUtil.debug
          console.log('done discontinuedDate')
        callback(null, true)
      )
  , (err, result) ->
    if err
      console.error(err)
      return
    if Meteor.gritsUtil.debug
      console.log('end sync [i18n, airports, effectiveDateMinMax, discontinuedDateMinMax] (ms): ', new Date() - start)
    # Hide the gritsOverlay indicator
    Session.set 'loading', false
    # Determine if the router set the simId in the url
    simId = Session.get(GritsConstants.SESSION_KEY_SHARED_SIMID)
    if !_.isUndefined(simId)
      Session.set GritsConstants.SESSION_KEY_MODE, GritsConstants.MODE_ANALYZE
    else
      Session.set GritsConstants.SESSION_KEY_MODE, GritsConstants.MODE_EXPLORE

    # Mark the app ready
    Session.set GritsConstants.SESSION_KEY_IS_READY, true
  )

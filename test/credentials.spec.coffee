helpers = require('./helpers')
AWS = helpers.AWS

validateCredentials = (creds, key, secret, session) ->
  expect(creds.accessKeyId).to.equal(key || 'akid')
  expect(creds.secretAccessKey).to.equal(secret || 'secret')
  expect(creds.sessionToken).to.equal(session || 'session')

describe 'AWS.Credentials', ->
  describe 'constructor', ->
    it 'should allow setting of credentials with keys', ->
      config = new AWS.Config(
        accessKeyId: 'akid'
        secretAccessKey: 'secret'
        sessionToken: 'session'
      )
      validateCredentials(config.credentials)

    it 'should allow setting of credentials as object', ->
      creds =
        accessKeyId: 'akid'
        secretAccessKey: 'secret'
        sessionToken: 'session'
      validateCredentials(new AWS.Credentials(creds))

    it 'defaults credentials to undefined when not passed', ->
      creds = new AWS.Credentials()
      expect(creds.accessKeyId).to.equal(undefined)
      expect(creds.secretAccessKey).to.equal(undefined)
      expect(creds.sessionToken).to.equal(undefined)

  describe 'needsRefresh', ->
    it 'needs refresh if credentials are not set', ->
      creds = new AWS.Credentials()
      expect(creds.needsRefresh()).to.equal(true)
      creds = new AWS.Credentials('akid')
      expect(creds.needsRefresh()).to.equal(true)

    it 'does not need refresh if credentials are set', ->
      creds = new AWS.Credentials('akid', 'secret')
      expect(creds.needsRefresh()).to.equal(false)

    it 'needs refresh if creds are expired', ->
      creds = new AWS.Credentials('akid', 'secret')
      creds.expired = true
      expect(creds.needsRefresh()).to.equal(true)

    it 'can be expired based on expireTime', ->
      creds = new AWS.Credentials('akid', 'secret')
      creds.expired = false
      creds.expireTime = new Date(0)
      expect(creds.needsRefresh()).to.equal(true)

    it 'needs refresh if expireTime is within expiryWindow secs from now', ->
      creds = new AWS.Credentials('akid', 'secret')
      creds.expired = false
      creds.expireTime = new Date(AWS.util.date.getDate().getTime() + 1000)
      expect(creds.needsRefresh()).to.equal(true)

    it 'does not need refresh if expireTime outside expiryWindow', ->
      creds = new AWS.Credentials('akid', 'secret')
      creds.expired = false
      ms = AWS.util.date.getDate().getTime() + (creds.expiryWindow + 5) * 1000
      creds.expireTime = new Date(ms)
      expect(creds.needsRefresh()).to.equal(false)

  describe 'get', ->
    it 'does not call refresh if not needsRefresh', ->
      spy = helpers.createSpy('done callback')
      creds = new AWS.Credentials('akid', 'secret')
      refresh = helpers.spyOn(creds, 'refresh')
      creds.get(spy)
      expect(refresh.calls.length).to.equal(0)
      expect(spy.calls.length).not.to.equal(0)
      expect(spy.calls[0].arguments[0]).not.to.exist
      expect(creds.expired).to.equal(false)

    it 'calls refresh only if needsRefresh', ->
      spy = helpers.createSpy('done callback')
      creds = new AWS.Credentials('akid', 'secret')
      creds.expired = true
      refresh = helpers.spyOn(creds, 'refresh').andCallThrough()
      creds.get(spy)
      expect(refresh.calls.length).not.to.equal(0)
      expect(spy.calls.length).not.to.equal(0)
      expect(spy.calls[0].arguments[0]).not.to.exist
      expect(creds.expired).to.equal(false)

if AWS.util.isNode()
  describe 'AWS.EnvironmentCredentials', ->
    beforeEach (done) ->
      process.env = {}
      done()

    afterEach ->
      process.env = {}

    describe 'constructor', ->
      it 'should be able to read credentials from env with a prefix', ->
        process.env.AWS_ACCESS_KEY_ID = 'akid'
        process.env.AWS_SECRET_ACCESS_KEY = 'secret'
        process.env.AWS_SESSION_TOKEN = 'session'
        creds = new AWS.EnvironmentCredentials('AWS')
        validateCredentials(creds)

      it 'should be able to read credentials from env without a prefix', ->
        process.env.ACCESS_KEY_ID = 'akid'
        process.env.SECRET_ACCESS_KEY = 'secret'
        process.env.SESSION_TOKEN = 'session'
        creds = new AWS.EnvironmentCredentials()
        validateCredentials(creds)

    describe 'refresh', ->
      it 'can refresh credentials', ->
        process.env.AWS_ACCESS_KEY_ID = 'akid'
        process.env.AWS_SECRET_ACCESS_KEY = 'secret'
        creds = new AWS.EnvironmentCredentials('AWS')
        expect(creds.accessKeyId).to.equal('akid')
        creds.accessKeyId = 'not_akid'
        expect(creds.accessKeyId).not.to.equal('akid')
        creds.refresh()
        expect(creds.accessKeyId).to.equal('akid')

  describe 'AWS.FileSystemCredentials', ->
    describe 'constructor', ->
      it 'should accept filename and load credentials from root doc', ->
        mock = '{"accessKeyId":"akid", "secretAccessKey":"secret","sessionToken":"session"}'
        helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        creds = new AWS.FileSystemCredentials('foo')
        validateCredentials(creds)

      it 'should accept filename and load credentials from credentials block', ->
        mock = '{"credentials":{"accessKeyId":"akid", "secretAccessKey":"secret","sessionToken":"session"}}'
        spy = helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        creds = new AWS.FileSystemCredentials('foo')
        validateCredentials(creds)

    describe 'refresh', ->
      it 'should refresh from given filename', ->
        mock = '{"credentials":{"accessKeyId":"RELOADED", "secretAccessKey":"RELOADED","sessionToken":"RELOADED"}}'
        helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        creds = new AWS.FileSystemCredentials('foo')
        validateCredentials(creds, 'RELOADED', 'RELOADED', 'RELOADED')

      it 'fails if credentials are not in the file', ->
        mock = '{"credentials":{}}'
        helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        new AWS.FileSystemCredentials('foo').refresh (err) ->
          expect(err.message).to.equal('Credentials not set in foo')

        expect(-> new AWS.FileSystemCredentials('foo').refresh()).
          to.throw('Credentials not set in foo')

  describe 'AWS.SharedIniFileCredentials', ->
    beforeEach ->
      delete process.env.AWS_PROFILE
      delete process.env.HOME
      delete process.env.HOMEPATH
      delete process.env.HOMEDRIVE
      delete process.env.USERPROFILE

    describe 'constructor', ->
      it 'throws an error if HOME/HOMEPATH/USERPROFILE are not set', ->
        expect(-> new AWS.SharedIniFileCredentials().refresh()).
          to.throw('Cannot load credentials, HOME path not set')

      it 'uses HOMEDRIVE\\HOMEPATH if HOME and USERPROFILE are not set', ->
        process.env.HOMEDRIVE = 'd:/'
        process.env.HOMEPATH = 'homepath'
        creds = new AWS.SharedIniFileCredentials()
        creds.get();
        expect(creds.filename).to.match(/d:[\/\\]homepath[\/\\].aws[\/\\]credentials/)

      it 'uses default HOMEDRIVE of C:/', ->
        process.env.HOMEPATH = 'homepath'
        creds = new AWS.SharedIniFileCredentials()
        creds.get();
        expect(creds.filename).to.match(/C:[\/\\]homepath[\/\\].aws[\/\\]credentials/)

      it 'uses USERPROFILE if HOME is not set', ->
        process.env.USERPROFILE = '/userprofile'
        creds = new AWS.SharedIniFileCredentials()
        creds.get();
        expect(creds.filename).to.match(/[\/\\]userprofile[\/\\].aws[\/\\]credentials/)

      it 'can override filename as a constructor argument', ->
        creds = new AWS.SharedIniFileCredentials(filename: '/etc/creds')
        creds.get();
        expect(creds.filename).to.equal('/etc/creds')

    describe 'loading', ->
      beforeEach -> process.env.HOME = '/home/user'

      it 'loads credentials from ~/.aws/credentials using default profile', ->
        mock = '''
        [default]
        aws_access_key_id = akid
        aws_secret_access_key = secret
        aws_session_token = session
        '''
        helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        creds = new AWS.SharedIniFileCredentials()
        creds.get();
        validateCredentials(creds)
        expect(AWS.util.readFileSync.calls[0].arguments[0]).to.match(/[\/\\]home[\/\\]user[\/\\].aws[\/\\]credentials/)

      it 'loads the default profile if AWS_PROFILE is empty', ->
        process.env.AWS_PROFILE = ''
        mock = '''
        [default]
        aws_access_key_id = akid
        aws_secret_access_key = secret
        aws_session_token = session
        '''
        helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        creds = new AWS.SharedIniFileCredentials()
        creds.get();
        validateCredentials(creds)

      it 'accepts a profile name parameter', ->
        mock = '''
        [foo]
        aws_access_key_id = akid
        aws_secret_access_key = secret
        aws_session_token = session
        '''
        spy = helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        creds = new AWS.SharedIniFileCredentials(profile: 'foo')
        creds.get();
        validateCredentials(creds)

      it 'sets profile based on ENV', ->
        process.env.AWS_PROFILE = 'foo'
        mock = '''
        [foo]
        aws_access_key_id = akid
        aws_secret_access_key = secret
        aws_session_token = session
        '''
        spy = helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        creds = new AWS.SharedIniFileCredentials()
        creds.get();
        validateCredentials(creds)

    describe 'refresh', ->
      beforeEach -> process.env.HOME = '/home/user'

      it 'should refresh from disk', ->
        mock = '''
        [default]
        aws_access_key_id = RELOADED
        aws_secret_access_key = RELOADED
        aws_session_token = RELOADED
        '''
        helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        creds = new AWS.SharedIniFileCredentials()
        creds.get();
        validateCredentials(creds, 'RELOADED', 'RELOADED', 'RELOADED')

      it 'fails if credentials are not in the file', ->
        mock = ''
        helpers.spyOn(AWS.util, 'readFileSync').andReturn(mock)

        new AWS.SharedIniFileCredentials().refresh (err) ->
          expect(err.message).to.match(/Profile default not found in [\/\\]home[\/\\]user[\/\\].aws[\/\\]credentials/)

        expect(-> new AWS.SharedIniFileCredentials().refresh()).
          to.throw(/Profile default not found in [\/\\]home[\/\\]user[\/\\].aws[\/\\]credentials/)

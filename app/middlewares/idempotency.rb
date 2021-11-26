class Idempotency
  def initialize(app)
    @app = app
  end

  def redis
    @redis ||= Redis.current
  end

  def call(env)
    @req = Rack::Request.new(env)
    @current_time = Time.now
    @key_in_header = env['HTTP_IDEMPOTENCY_KEY']

    return [400, {}, ['']] if @key_in_header.blank?

    if redis.hexists(@key_in_header, 'key')
      if equivalent_request?
        [recorded_request(:status), JSON.parse(recorded_request(:headers)), JSON.parse(recorded_request(:body))]
      else
        [422, {}, ['']]
      end
    else
      call_with_record_request(env)
    end
  end

  def equivalent_request?
    @req.request_method == recorded_request(:method) && @req.body.string == recorded_request(:params) && @req.path == recorded_request(:path)
  end

  def recorded_request(key)
    redis.hget @key_in_header, key.to_s
  end

  def call_with_record_request(env)
    status, headers, body = @app.call(env)

    {
      key: @key_in_header,
      method: @req.request_method,
      params: @req.body.string,
      path: @req.path,
      status: status,
      headers: headers.to_json,
      body: body.each(&:to_s).to_json
    }.each do |k, v|
      redis.hset @key_in_header, k.to_s, v
    end

    [status, headers, body]
  end
end

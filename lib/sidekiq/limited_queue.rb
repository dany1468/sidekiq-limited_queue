require 'sidekiq'
require 'sidekiq/limited_queue/version'

module Sidekiq
  module LimitedQueue
    class Middleware
      LUA_CACHE = {}
      LimitedQueueConfig = Struct.new(:limit_size, :delay_second)

      # {slow: 1}
      # {slow: [1, 30]} -> {queue_name: [limit_size, delay_second_if_limited]}
      def initialize(queue_limit_map = {})
        @queue_limit_map = queue_limit_map.each_with_object({}) {|(k, v), h|
          if Array === v
            h[k] = LimitedQueueConfig.new(v.first, v.last)
          else
            h[k] = LimitedQueueConfig.new(v, 0)
          end
        }
      end

      def call(_worker, msg, queue)
        unless limited_queue?(queue)
          yield
        else
          unless attempt_to_lock(queue)
            requeue(queue, msg)

            return
          end

          begin
            yield
          ensure
            release_lock queue
          end
        end
      end

      def limited_queue?(queue)
        @queue_limit_map.key?(queue.to_sym)
      end

      def attempt_to_lock(queue)
        !(redis_eval :busy, [namespace, queue, @queue_limit_map[queue.to_sym].limit_size])
      end

      def release_lock(queue)
        redis_eval :release, [namespace, queue]
      end

      def requeue(queue_name, msg)
        Sidekiq.redis do |r|
          payload = Sidekiq.dump_json(msg)

          if (delay_second = @queue_limit_map[queue_name.to_sym].delay_second) > 0
            r.zadd('retry', (Time.now.to_f + delay_second).to_s, payload)
          else
            r.rpush("queue:#{queue_name}", payload)
          end
        end
      end

      def redis_eval(script_name, args)
        Sidekiq.redis {|r|
          begin
            r.evalsha send("redis_#{script_name}_sha"), argv: args
          rescue Redis::CommandError => e
            raise unless e.message.include? 'NOSCRIPT'

            LUA_CACHE.clear
            retry
          end
        }
      end

      def redis_busy_sha
        unless LUA_CACHE.key?(:busy_sha)
          LUA_CACHE[:busy_sha] = Sidekiq.redis {|r| r.script(:load, redis_busy_script) }
        end

        LUA_CACHE[:busy_sha]
      end

      def redis_release_sha
        unless LUA_CACHE.key?(:release_sha)
          LUA_CACHE[:release_sha] = Sidekiq.redis {|r| r.script(:load, redis_release_script) }
        end

        LUA_CACHE[:release_sha]
      end

      def namespace
        @namespace ||= Sidekiq.redis {|r|
          if r.respond_to?(:namespace) and r.namespace
            "#{r.namespace}:"
          else
            ''
          end
        }
      end

      def redis_busy_script
        <<-LUA
          local namespace = table.remove(ARGV, 1)..'limit_fetch:'
          local queue = table.remove(ARGV, 1)
          local limit = table.remove(ARGV, 1)
          limit = tonumber(limit)

          if limit == 0 then
            return false
          end

          local busy_key = namespace..'busy:'..queue
          local probed_key = namespace..'probed:'..queue
          local limit_key = namespace..'limit:'..queue

          local busy = redis.call('get', busy_key)

          if busy == 'true' then
            return true
          end

          local locks = redis.call('get', probed_key)
          locks = tonumber(locks or 0)

          if limit > locks then
            if limit == (locks + 1) then
              redis.call('set', busy_key, 'true')
            end

            redis.call('incr', probed_key)
            return false
          end

          return true
        LUA
      end

      def redis_release_script
        <<-LUA
          local namespace = table.remove(ARGV, 1)..'limit_fetch:'
          local queue = table.remove(ARGV, 1)

          local busy_key = namespace..'busy:'..queue
          local probed_key = namespace..'probed:'..queue

          local locks = redis.call('get', probed_key)
          locks = tonumber(locks or 0)

          if locks > 0 then
            redis.call('decr', probed_key)
          end
          redis.call('set', busy_key, 'false')
        LUA
      end
    end
  end
end

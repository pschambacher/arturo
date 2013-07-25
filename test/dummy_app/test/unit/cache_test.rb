require File.expand_path('../../test_helper', __FILE__)
require 'arturo/features_helper'

class CacheTest < ActiveSupport::TestCase

  Arturo::Feature.extend(Arturo::FeatureCaching)

  class StupidCache
    def initialize(enabled=true)
      @enabled = enabled
      @data = {}
    end

    def read(key)
      @data[key] if @enabled
    end

    def write(key, value, options={})
      @data[key] = value
    end

    def clear
      @data.clear
    end
  end

  def setup
    @feature = create(:feature)
    Arturo::Feature.cache_ttl = 30.minutes
    Arturo::Feature.feature_cache.clear
  end

  def teardown
    Arturo::Feature.cache_ttl = 0 # turn off for other tests
    Timecop.return
  end

  def test_first_load_hits_database
    Arturo::Feature.expects(:where).once.returns([@feature.reload])
    Arturo::Feature.to_feature(@feature.symbol)
  end

  def test_subsequent_loads_within_ttl_hit_cache
    Arturo::Feature.expects(:where).once.returns([@feature.reload])
    Arturo::Feature.to_feature(@feature.symbol)
    Arturo::Feature.to_feature(@feature.symbol)
    Arturo::Feature.to_feature(@feature.symbol)
  end

  def test_no_such_feature_is_cached
    Arturo::Feature.expects(:where).once.returns([])
    assert_kind_of Arturo::NoSuchFeature, Arturo::Feature.to_feature(:ramen)
    assert_kind_of Arturo::NoSuchFeature, Arturo::Feature.to_feature(:ramen)
    assert_kind_of Arturo::NoSuchFeature, Arturo::Feature.to_feature(:ramen)
  end

  def test_works_with_other_cache_backend
    Arturo::Feature.feature_cache = StupidCache.new
    Arturo::Feature.expects(:where).once.returns([@feature.reload])
    Arturo::Feature.to_feature(@feature.symbol.to_sym)
    Arturo::Feature.to_feature(@feature.symbol)
    Arturo::Feature.to_feature(@feature.symbol.to_sym)
    Arturo::Feature.to_feature(@feature.symbol)
  end

  def test_works_with_inconsistent_cache_backend
    Arturo::Feature.feature_cache = StupidCache.new(false)
    Arturo::Feature.expects(:where).twice.returns([@feature])
    Arturo::Feature.to_feature(@feature.symbol.to_sym)
    Arturo::Feature.to_feature(@feature.symbol.to_sym)
  end

  def test_clear_cache
    Arturo::Feature.to_feature(@feature.symbol)
    Arturo::Feature.feature_cache.clear
    Arturo::Feature.expects(:where).once.returns([@feature.reload])
    Arturo::Feature.to_feature(@feature.symbol)
  end

  def test_turn_off_caching
    Arturo::Feature.cache_ttl = 0
    Arturo::Feature.expects(:where).twice.returns([@feature.reload])
    Arturo::Feature.to_feature(@feature.symbol)
    Arturo::Feature.to_feature(@feature.symbol)
  end

  def test_ttl_expiry
    Arturo::Feature.to_feature(@feature.symbol)
    Arturo::Feature.expects(:where).once.returns([@feature.reload])
    Timecop.travel(Time.now + Arturo::Feature.cache_ttl - 5.seconds)
    Arturo::Feature.to_feature(@feature.symbol)
    Timecop.travel(Time.now + Arturo::Feature.cache_ttl + 5.seconds)
    Arturo::Feature.to_feature(@feature.symbol)
  end

  def test_warm_cache
    second_feature = create(:feature)
    Arturo::Feature.warm_cache!

    Arturo::Feature.expects(:where).never
    assert_equal @feature, Arturo::Feature.to_feature(@feature.symbol)
    assert_equal second_feature, Arturo::Feature.to_feature(second_feature.symbol)
  end

  def test_expires_cache_on_enable_or_disable
    refute_equal 100, Arturo::Feature.to_feature(@feature.symbol).deployment_percentage

    Arturo.enable_feature!(@feature.symbol)
    assert_equal 100, Arturo::Feature.to_feature(@feature.symbol).deployment_percentage

    Arturo.disable_feature!(@feature.symbol)
    assert_equal 0, Arturo::Feature.to_feature(@feature.symbol).deployment_percentage
  end
end

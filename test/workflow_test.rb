# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require_relative "./support/setup"
require_relative "./support/sidekiq_batches"

class CustomErrorForTesting < StandardError; end

class WorkerWithEnqueueStep < Support::Sidekiq::Workflow
  include Sidekiq::Worker
  include AcidicJob

  class AsyncWorker < Support::Sidekiq::StepWorker
    def perform(_key_id)
      call_batch_success_callback
    end
  end

  def perform
    idempotently with: {} do
      step :enqueue_step, awaits: [AsyncWorker]
      step :next_step
    end
  end

  def next_step
    raise CustomErrorForTesting
  end
end

class TestWorkflows < Minitest::Test
  def setup
    @sidekiq_queue = Sidekiq::Queues["default"]
  end

  def before_setup
    super
    DatabaseCleaner.start
    Sidekiq::Queues.clear_all
  end

  def after_teardown
    Sidekiq::Queues.clear_all
    DatabaseCleaner.clean
    super
  end

  def assert_enqueued_with(worker:, args: [], size: 1)
    assert_equal size, @sidekiq_queue.size
    assert_equal worker.to_s, @sidekiq_queue.first["class"]
    assert_equal args, @sidekiq_queue.first["args"]
    @sidekiq_queue.clear
  end

  def mocking_sidekiq_batches(&block)
    Sidekiq::Batch.stub(:new, ->(*) { Support::Sidekiq::NullBatch.new }) do
      Sidekiq::Batch::Status.stub(:new, ->(*) { Support::Sidekiq::NullStatus.new }) do
        Sidekiq::Testing.inline! do
          block.call
        end
      end
    end
  end

  def test_step_with_enqueues_is_run_properly
    mocking_sidekiq_batches do
      assert_raises CustomErrorForTesting do
        WorkerWithEnqueueStep.initiate
      end
    end

    assert_equal 1, AcidicJob::Key.count
    assert_equal CustomErrorForTesting, AcidicJob::Key.first.error_object.class
  end
end
